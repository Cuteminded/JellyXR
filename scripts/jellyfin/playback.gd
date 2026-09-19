class_name PlaybackSession
extends Node

signal failed(message: String)
signal stream_ready(url: String, source: Dictionary, start_ms: int)

var api: JellyfinClient
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
	started = false
	var profile := {
		"Name": "Jellyframe SDR " + OS.get_name(),
		"MaxStreamingBitrate": 80000000,
		"DirectPlayProfiles": [] if transcode else [{"Container": "mp4,m4v,mkv,webm", "Type": "Video", "VideoCodec": "h264,hevc,vp9", "AudioCodec": "aac,mp3,opus,vorbis"}],
		"TranscodingProfiles": [{"Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac", "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "2", "MinSegments": 2, "BreakOnNonKeyFrames": true}],
		"CodecProfiles": [{"Type": "Video", "Conditions": [{"Condition": "Equals", "Property": "VideoRangeType", "Value": "SDR", "IsRequired": true}]}],
		"SubtitleProfiles": []
	}
	var result := await api.request("/Items/%s/PlaybackInfo" % str(item.Id).uri_encode(), HTTPClient.METHOD_POST, {
		"UserId": api.user_id, "StartTimeTicks": position_ticks, "IsPlayback": true,
		"AutoOpenLiveStream": true, "EnableDirectPlay": not transcode, "EnableDirectStream": false,
		"EnableTranscoding": true, "DeviceProfile": profile, "MaxStreamingBitrate": 80000000
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
	if source.get("SupportsDirectPlay", false) and not transcode:
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
	stream_ready.emit(url, source, start_ms)

func retry_transcode() -> void:
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
