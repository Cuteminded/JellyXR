extends SceneTree

class FixtureClient extends JellyfinClient:
	var bodies: Array[Dictionary] = []
	var direct := true
	var transcode_path := "/Videos/fixture/master.m3u8"
	var sources: Array = []

	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
		bodies.append(body)
		if not sources.is_empty(): return {"ok": true, "data": {"MediaSources": sources, "PlaySessionId": "versions"}}
		return {"ok": true, "data": {"MediaSources": [{"Id": "fixture-source", "SupportsDirectPlay": direct, "TranscodingUrl": transcode_path}]}}

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
	assert(session.method == "Transcode" and streams[1][1] == 30000, "HLS resumes at the absolute position in the decoder")
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
	await check_playback_choices(session, api, streams)
	await check_transcode_resolutions(session, api, streams)
	await check_media_versions(session, api, streams)
	session.queue_free()
	api.queue_free()
	print("Playback profile checks: PASS")
	quit()

func check_media_versions(session: PlaybackSession, api: FixtureClient, streams: Array) -> void:
	api.sources = [
		{"Id": "first", "SupportsDirectPlay": true, "TranscodingUrl": "/first.m3u8"},
		{"Id": "second", "SupportsDirectPlay": true, "TranscodingUrl": "/second.m3u8"}
	]
	var selected := {"Id": "fixture", "SelectedMediaSourceId": "second", "UserData": {"PlaybackPositionTicks": 450000000}}
	await session.open(selected)
	assert(api.bodies.back().MediaSourceId == "second", "Negotiation requests the selected version")
	assert("MediaSourceId=second" in streams.back()[0] and streams.back()[1] == 45000, "Direct playback resumes the selected version even when it is returned second")
	await session.report("Playing")
	assert(api.bodies.back().MediaSourceId == "second", "Playback reports identify the selected version")
	await session.retry_transcode()
	assert(api.bodies.back().MediaSourceId == "second" and streams.back()[0].contains("/second.m3u8"), "Decoder fallback keeps the selected version")
	session.position_ticks = 900000000
	await session.open(selected, true)
	assert(api.bodies.back().MediaSourceId == "second" and streams.back()[1] == 90000, "Transcoded seeks keep the version and absolute position")
	var errors: Array = []
	session.failed.connect(func(message: String): errors.append(message))
	api.sources.remove_at(1)
	var count := streams.size()
	await session.open(selected)
	assert(streams.size() == count and errors.size() == 1, "A missing version fails instead of playing another version")
	await session.open({"Id": "another-item"})
	assert(not api.bodies.back().has("MediaSourceId") and session.media_source_id == "first", "A new item clears the previous version choice")

func check_playback_choices(session: PlaybackSession, api: FixtureClient, streams: Array) -> void:
	session.settings = JellyXRSettings.new()
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
	assert(api.bodies.back().StartTimeTicks == 450000000 and streams.back()[1] == 45000, "Forced HLS conversion preserves the resume position in the decoder")
	session.settings.playback_mode = "original"
	session.position_ticks = 900000000
	await session.open(session.item, true)
	assert(session.method == "Transcode" and api.bodies.back().StartTimeTicks == 900000000, "Seeking keeps the active playback choice even if the next-video preference changes")
	assert(streams.back()[1] == 90000, "Reopened HLS streams retain the requested decoder position")
	api.transcode_path = "/Videos/fixture/stream.mp4?StartTimeTicks=900000000"
	await session.open(session.item, true)
	assert(not session.is_hls() and streams.back()[1] == 0, "Progressive transcoding starts at the server offset without a second decoder seek")
	session.source["TranscodingSubProtocol"] = "hls"
	assert(session.is_hls(), "The advertised HLS protocol is recognized without a playlist extension")

func check_transcode_resolutions(session: PlaybackSession, api: FixtureClient, streams: Array) -> void:
	session.settings.playback_mode = "transcoded"
	api.direct = true
	api.transcode_path = "/Videos/fixture/master.m3u8"
	for sample in [[720, "1280", "720", "6000000"], [1080, "1920", "1080", "12000000"], [2160, "3840", "2160", "40000000"]]:
		session.settings.transcode_resolution = sample[0]
		await session.open({"Id": "fixture", "UserData": {"PlaybackPositionTicks": 450000000}})
		var request: Dictionary = api.bodies.back()
		var expected := {"Width": sample[1], "Height": sample[2], "VideoFramerate": "30", "VideoBitrate": sample[3]}
		var limits := {}
		for condition in request.DeviceProfile.TranscodingProfiles[0].Conditions:
			assert(condition.Condition == "LessThanEqual", "Resolution choices set a maximum and do not force upscaling")
			limits[condition.Property] = condition.Value
		assert(limits == expected, "Each resolution sends its own dimensions and bitrate budget")
		for condition in request.DeviceProfile.CodecProfiles[0].Conditions:
			if expected.has(condition.Property):
				assert(condition.Value == expected[condition.Property], "Codec limits match the selected conversion quality")
		assert(not request.EnableDirectPlay and not request.AllowVideoStreamCopy, "Each resolution forces conversion even for a directly playable source")
		assert(streams.back()[1] == 45000, "Each resolution preserves the HLS resume position")

	session.settings.transcode_resolution = 720
	session.position_ticks = 900000000
	await session.open(session.item, true)
	assert(session.active_transcode_resolution == 2160 and streams.back()[1] == 90000, "Seeking keeps the active 4K quality and requested position")
	await session.open({"Id": "fixture"})
	assert(session.active_transcode_resolution == 720, "A new video uses the updated resolution preference")
	session.settings.playback_mode = "auto"
	session.settings.transcode_resolution = 2160
	await session.open({"Id": "fixture"})
	assert(session.method == "DirectPlay" and session.active_transcode_resolution == 1080, "Automatic playback keeps its existing direct-play and conversion defaults")
	await session.retry_transcode()
	assert(session.method == "Transcode" and session.active_transcode_resolution == 1080, "Automatic recovery retains its existing 1080p conversion default")
