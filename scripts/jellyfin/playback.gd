class_name PlaybackSession
extends Node

signal failed(message: String)
signal stream_ready(url: String, source: Dictionary, start_ms: int)

var api: JellyfinClient
var settings: JellyframeSettings
var active_playback_mode := "auto"
var active_transcode_resolution := 1080
var item: Dictionary = {}
var source: Dictionary = {}
var session_id := ""
var method := "DirectPlay"
var position_ticks := 0
var started := false
var fallback_attempted := false

func open(selected: Dictionary, transcode: bool = false) -> void:
	item = selected
	if not transcode:
		position_ticks = int(item.get("UserData", {}).get("PlaybackPositionTicks", 0))
		fallback_attempted = false
		active_playback_mode = settings.playback_mode if settings != null else "auto"
		active_transcode_resolution = settings.transcode_resolution if settings != null and active_playback_mode == "transcoded" else 1080
	started = false
	var use_transcode := transcode or active_playback_mode == "transcoded"
	var original := active_playback_mode == "original"
	var profile := _device_profile(use_transcode, original)
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
		if not is_hls(): start_ms = 0
	stream_ready.emit(url, source, start_ms)

func is_hls() -> bool:
	if method != "Transcode": return false
	var protocol := str(source.get("TranscodingSubProtocol", "")).to_lower()
	var path := str(source.get("TranscodingUrl", "")).get_slice("?", 0).to_lower()
	return protocol == "hls" or path.ends_with(".m3u8")

func _device_profile(transcode: bool, original: bool = false) -> Dictionary:
	var direct_profile := {"Container": "mp4,m4v,mkv,webm", "Type": "Video"}
	if not original:
		direct_profile["VideoCodec"] = "h264,hevc,vp9"
		direct_profile["AudioCodec"] = "aac,mp3,opus,vorbis"
	var transcoding_profile := {"Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac", "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "2", "MinSegments": 2, "BreakOnNonKeyFrames": true}
	var codec_conditions := [{"Condition": "Equals", "Property": "VideoRangeType", "Value": "SDR", "IsRequired": true}]
	var preset: Dictionary = JellyframeSettings.TRANSCODE_PRESETS.get(active_transcode_resolution, JellyframeSettings.TRANSCODE_PRESETS[1080])
	transcoding_profile["Conditions"] = []
	for limit in [["Width", str(preset.width)], ["Height", str(preset.height)], ["VideoFramerate", "30"], ["VideoBitrate", str(preset.bitrate)]]:
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
	if event == "Stopped":
		started = false
		if method == "Transcode":
			await api.request("/Videos/ActiveEncodings" + api.query({"DeviceId": api.device_id, "PlaySessionId": session_id}), HTTPClient.METHOD_DELETE)
