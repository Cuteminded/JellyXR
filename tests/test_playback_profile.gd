extends SceneTree

class FixtureClient extends JellyfinClient:
	var bodies: Array[Dictionary] = []
	var direct := true
	var diagnostics_path := ""

	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
		if path.begins_with("/Sessions?"):
			diagnostics_path = path
			return {"ok": true, "data": [null, {"DeviceId": device_id, "NowPlayingItem": null}, {"DeviceId": device_id, "NowPlayingItem": {"Id": "fixture"}, "TranscodingInfo": null}]}
		bodies.append(body)
		return {"ok": true, "data": {"MediaSources": [{"Id": "fixture-source", "SupportsDirectPlay": direct, "TranscodingUrl": "/Videos/fixture/master.m3u8"}]}}

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var session := PlaybackSession.new()
	root.add_child(session)
	var api := FixtureClient.new()
	api.server = "https://fixture.invalid"
	root.add_child(api)
	session.api = api
	var streams: Array = []
	session.stream_ready.connect(func(url: String, _source: Dictionary, start_ms: int): streams.append([url, start_ms]))
	await session.open({"Id": "fixture", "UserData": {"PlaybackPositionTicks": 300000000}})
	assert(session.method == "DirectPlay" and streams[0][1] == 30000, "Compatible titles keep direct playback and the resume position")
	assert("Static=true" in streams[0][0], "Direct playback uses the original file")
	api.direct = false
	await session.open({"Id": "fixture"}, true)
	assert(session.method == "Transcode" and streams[1][1] == 0, "Converted streams start at the server-requested offset")
	assert(not api.bodies[1].EnableDirectPlay and api.bodies[1].DeviceProfile.DirectPlayProfiles.is_empty(), "Recovery requests conversion instead of the failed direct stream")
	var automatic_profile := session._device_profile(false)
	assert(automatic_profile.MaxStreamingBitrate == 80000000, "Direct playback retains its original bitrate budget")
	assert(not automatic_profile.DirectPlayProfiles.is_empty(), "Automatic mode still negotiates original-quality direct playback")
	assert(automatic_profile.CodecProfiles.size() == 1, "Transcoding limits do not restrict direct-play codecs")
	var limits: Dictionary = {}
	for condition in automatic_profile.TranscodingProfiles[0].Conditions:
		assert(condition.Condition == "LessThanEqual", "Transcoding uses maximum values rather than fixed dimensions")
		limits[condition.Property] = condition.Value
	assert(limits == {"Width": "1920", "Height": "1080", "VideoFramerate": "30", "VideoBitrate": "12000000"}, "Conversion requests a lower-cost output on PC and Android")
	var retry_profile := session._device_profile(true)
	assert(retry_profile.DirectPlayProfiles.is_empty(), "Decoder recovery disables the failed direct-play path")
	assert(retry_profile.TranscodingProfiles == automatic_profile.TranscodingProfiles, "Decoder recovery retains conversion limits")
	assert(api.bodies[1].DeviceProfile.TranscodingProfiles[0].Conditions == retry_profile.TranscodingProfiles[0].Conditions, "The playback request sends the conversion limits on the current platform")
	api.device_id = "fixture device"
	await session._log_transcoding()
	assert(api.diagnostics_path == "/Sessions?DeviceId=fixture%20device", "Diagnostics request only the current device and escape its identifier")
	assert(not session.diagnostics_pending, "Inactive sessions finish diagnostics without a stuck pending request")
	await check_playback_choices(session, api, streams)
	session.queue_free()
	api.queue_free()
	print("Playback profile checks: PASS")
	quit()

func check_playback_choices(session: PlaybackSession, api: FixtureClient, streams: Array) -> void:
	session.settings = JellyframeSettings.new()
	session.settings.playback_mode = "original"
	api.direct = true
	await session.open({"Id": "fixture"})
	assert(session.method == "DirectPlay" and not api.bodies.back().EnableTranscoding, "Original playback disables server conversion")
	assert(api.bodies.back().DeviceProfile.CodecProfiles.is_empty(), "Original playback does not force SDR conversion")
	assert(not api.bodies.back().DeviceProfile.DirectPlayProfiles[0].has("VideoCodec"), "Original playback lets the user try AV1 without conversion")
	var failures: Array[String] = []
	session.failed.connect(func(message: String): failures.append(message))
	var requests_before := api.bodies.size()
	await session.retry_transcode()
	assert(api.bodies.size() == requests_before and failures.size() == 1, "Original playback errors never silently downgrade to transcoding")
	api.direct = false
	var streams_before := streams.size()
	await session.open({"Id": "fixture"})
	assert(streams.size() == streams_before and failures.size() == 2, "Unsupported original playback reports an error instead of opening a converted stream")
	session.settings.playback_mode = "transcoded"
	api.direct = true
	await session.open({"Id": "fixture", "UserData": {"PlaybackPositionTicks": 450000000}})
	assert(session.method == "Transcode" and not api.bodies.back().EnableDirectPlay, "Transcoded playback bypasses a supported original stream")
	assert(not api.bodies.back().AllowVideoStreamCopy, "Transcoded playback requests actual video conversion")
	assert(api.bodies.back().StartTimeTicks == 450000000 and streams.back()[1] == 0, "Forced conversion preserves the server resume offset")
	session.settings.playback_mode = "original"
	session.position_ticks = 900000000
	await session.open(session.item, true)
	assert(session.method == "Transcode" and api.bodies.back().StartTimeTicks == 900000000, "Seeking keeps the active playback choice even if the next-video preference changes")
