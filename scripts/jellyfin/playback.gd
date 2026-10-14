class_name PlaybackSession
extends Node

signal failed(message: String)
signal stream_ready(url: String, source: Dictionary, start_ms: int)

var api: JellyfinClient
var settings: JellyframeSettings
var active_playback_mode := "auto"
var item: Dictionary = {}
var source: Dictionary = {}
var session_id := ""
var method := "DirectPlay"
var position_ticks := 0
var started := false
var fallback_attempted := false
var diagnostics_pending := false

func open(selected: Dictionary, transcode: bool = false) -> void:
	item = selected
	if not transcode:
		position_ticks = int(item.get("UserData", {}).get("PlaybackPositionTicks", 0))
		fallback_attempted = false
		active_playback_mode = settings.playback_mode if settings != null else "auto"
	started = false
	var use_transcode := transcode or active_playback_mode == "transcoded"
	var original := active_playback_mode == "original"
	var profile := _device_profile(use_transcode, OS.get_name() == "Android", original)
	if not use_transcode:
		print("Jellyframe playback: direct codecs=", profile.DirectPlayProfiles[0].get("VideoCodec", "original formats"))
	var result := await api.request("/Items/%s/PlaybackInfo" % str(item.Id).uri_encode(), HTTPClient.METHOD_POST, {
		"UserId": api.user_id, "StartTimeTicks": position_ticks, "IsPlayback": true,
		"AutoOpenLiveStream": true, "EnableDirectPlay": not use_transcode, "EnableDirectStream": false,
		"EnableTranscoding": not original, "AllowVideoStreamCopy": not use_transcode,
		"DeviceProfile": profile, "MaxStreamingBitrate": profile.MaxStreamingBitrate
	})
	if not result.ok:
		failed.emit(result.error)
		return
	if result.data.get("MediaSources", []).is_empty():
		failed.emit("Jellyfin could not provide a video stream. Check your account's playback permissions.")
		return
	source = result.data.MediaSources[0]
	session_id = result.data.get("PlaySessionId", "")
	var url: String
	var start_ms := int(position_ticks / 10000)
	if original and not source.get("SupportsDirectPlay", false):
		failed.emit("Jellyfin cannot provide the original video. Choose Transcoded in Settings > Playback.")
		return
	if source.get("SupportsDirectPlay", false) and not use_transcode:
		method = "DirectPlay"
		url = api.server + "/Videos/%s/stream" % str(item.Id).uri_encode() + api.query({"Static": "true", "MediaSourceId": source.Id})
	else:
		method = "Transcode"
		var path: String = source.get("TranscodingUrl", "")
		if path.is_empty():
			failed.emit("Jellyfin needs to convert this video but did not provide a stream.")
			return
		url = api.stream_url(path)
		if url.is_empty():
			failed.emit("The server returned an unsupported stream address.")
			return
		start_ms = 0
	print("Jellyframe playback: method=", method, ", bitrate=", source.get("Bitrate", 0), ", transcode reasons=", source.get("TranscodeReasons", []))
	for track in source.get("MediaStreams", []):
		if track.get("Type", "") == "Video":
			print("Jellyframe playback: codec=", track.get("Codec", "unknown"), ", size=", track.get("Width", 0), "x", track.get("Height", 0), ", range=", track.get("VideoRangeType", "unknown"), ", fps=", track.get("AverageFrameRate", 0))
			break
	stream_ready.emit(url, source, start_ms)

func _device_profile(transcode: bool, android: bool, original: bool = false) -> Dictionary:
	var direct_profile := {"Container": "mp4,m4v,mkv,webm", "Type": "Video"}
	if not original:
		direct_profile["VideoCodec"] = "h264,hevc,vp9"
		direct_profile["AudioCodec"] = "aac,mp3,opus,vorbis"
	var transcoding_profile := {"Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac", "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "2", "MinSegments": 2, "BreakOnNonKeyFrames": true}
	var codec_conditions := [{"Condition": "Equals", "Property": "VideoRangeType", "Value": "SDR", "IsRequired": true}]
	if android:
		transcoding_profile["Conditions"] = []
		for limit in [["Width", "1920"], ["Height", "1080"], ["VideoFramerate", "30"], ["VideoBitrate", "12000000"]]:
			transcoding_profile.Conditions.append({"Condition": "LessThanEqual", "Property": limit[0], "Value": limit[1], "IsRequired": true})
		if transcode: codec_conditions.append_array(transcoding_profile.Conditions)
	return {
		"Name": ("Jellyframe original " if original else "Jellyframe SDR ") + OS.get_name(),
		"MaxStreamingBitrate": 2147483647 if original else 80000000,
		"DirectPlayProfiles": [] if transcode else [direct_profile],
		"TranscodingProfiles": [] if original else [transcoding_profile],
		"CodecProfiles": [] if original else [{"Type": "Video", "Conditions": codec_conditions}],
		"SubtitleProfiles": []
	}

func retry_transcode() -> void:
	if active_playback_mode == "original":
		failed.emit("The original video failed to play. Choose Transcoded in Settings > Playback.")
		return
	if fallback_attempted or method == "Transcode":
		failed.emit("Playback failed after Jellyfin tried to convert the video. Check the server's transcoding settings and logs.")
		return
	fallback_attempted = true
	await report("Stopped")
	await open(item, true)

func report(event: String, paused: bool = false) -> void:
	if session_id.is_empty(): return
	if event == "Playing": started = true
	if not started: return
	var path := "/Sessions/Playing" + ("/" + event if event != "Playing" else "")
	await api.request(path, HTTPClient.METHOD_POST, {"ItemId": item.Id, "MediaSourceId": source.Id, "PlaySessionId": session_id, "PositionTicks": position_ticks, "IsPaused": paused, "CanSeek": true, "PlayMethod": method})
	if event == "Progress" and method == "Transcode" and OS.is_debug_build() and not diagnostics_pending:
		_log_transcoding()
	if event == "Stopped":
		started = false
		if method == "Transcode":
			await api.request("/Videos/ActiveEncodings" + api.query({"DeviceId": api.device_id, "PlaySessionId": session_id}), HTTPClient.METHOD_DELETE)

func _log_transcoding() -> void:
	diagnostics_pending = true
	var result := await api.request("/Sessions" + api.query({"DeviceId": api.device_id}))
	diagnostics_pending = false
	if not result.ok or not result.data is Array: return
	for active in result.data:
		if not active is Dictionary: continue
		if str(active.get("DeviceId", "")) != api.device_id: continue
		var playing_item: Variant = active.get("NowPlayingItem")
		if not playing_item is Dictionary: continue
		if str(playing_item.get("Id", "")) != str(item.get("Id", "")): continue
		var info: Variant = active.get("TranscodingInfo")
		if not info is Dictionary: continue
		print("Jellyframe transcoding: fps=", info.get("Framerate"), ", bitrate=", info.get("Bitrate"), ", size=", info.get("Width"), "x", info.get("Height"), ", hardware=", info.get("HardwareAccelerationType"), ", video copy=", info.get("IsVideoDirect"), ", reasons=", info.get("TranscodeReasons"))
