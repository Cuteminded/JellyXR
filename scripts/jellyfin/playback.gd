class_name PlaybackSession
extends Node

signal failed(message: String)
signal stream_ready(url: String, source: Dictionary, start_ms: int)
signal reporting_failed(message: String)

const PC_VIDEO_CODECS := "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1,wmv3"
const PC_AUDIO_CODECS := "aac,mp3,opus,vorbis,flac,alac,ac3,eac3,dts,truehd,mp2,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le"
const PC_VIDEO_RANGES := "SDR|HDR10|HDR10Plus|HLG|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithHLG|DOVIWithSDR"

var api: JellyfinClient
var settings: JellyXRSettings
var video_backend: VideoBackend
var active_playback_mode := "auto"
var active_transcode_resolution := 1080
var active_transcode_max_fps := JellyXRSettings.DEFAULT_TRANSCODE_MAX_FPS
var item: Dictionary = {}
var source: Dictionary = {}
var session_id := ""
var method := "DirectPlay"
var position_ticks := 0
var started := false
var fallback_attempted := false
var media_source_id := ""
var audio_index := -1
var subtitle_index := -1
var burn_subtitles := false
var generation := 0

func open(selected: Dictionary, transcode: bool = false, continuing: bool = false) -> void:
	generation += 1
	var current := generation
	item = selected
	if not transcode and not continuing:
		audio_index = -1
		subtitle_index = -1
		burn_subtitles = false
		media_source_id = str(item.get("SelectedMediaSourceId", ""))
		if media_source_id.is_empty() and item.get("MediaSources") is Array and not item.MediaSources.is_empty():
			media_source_id = str(item.MediaSources[0].get("Id", ""))
		position_ticks = int(item.get("UserData", {}).get("PlaybackPositionTicks", 0))
		fallback_attempted = false
		active_playback_mode = settings.playback_mode if settings != null else "auto"
		active_transcode_resolution = settings.transcode_resolution if settings != null else 1080
		active_transcode_max_fps = settings.transcode_max_fps if settings != null else JellyXRSettings.DEFAULT_TRANSCODE_MAX_FPS
	started = false
	var use_transcode := transcode or burn_subtitles or active_playback_mode == "transcoded"
	var original := active_playback_mode == "original"
	var video_stream := _source_video(_selected_source(continuing))
	if not use_transcode and not original:
		use_transcode = _decode_support(video_stream) == VideoBackend.DecodeSupport.UNSUPPORTED
	var profile := _device_profile(use_transcode, original, str(video_stream.get("Codec", "")))
	if use_transcode and profile.TranscodingProfiles.is_empty():
		failed.emit("This device reported no supported H.264 conversion target for the selected playback limits.")
		return
	var body := {
		"UserId": api.user_id, "StartTimeTicks": position_ticks, "IsPlayback": true,
		"AutoOpenLiveStream": true, "EnableDirectPlay": not use_transcode and audio_index < 0, "EnableDirectStream": not use_transcode and not original,
		"EnableTranscoding": not original, "AllowVideoStreamCopy": not use_transcode,
		"DeviceProfile": profile, "MaxStreamingBitrate": profile.MaxStreamingBitrate
	}
	body["SubtitleStreamIndex"] = subtitle_index if burn_subtitles else -1
	if burn_subtitles: body["AlwaysBurnInSubtitleWhenTranscoding"] = true
	if audio_index >= 0: body["AudioStreamIndex"] = audio_index
	if not media_source_id.is_empty(): body["MediaSourceId"] = media_source_id
	var needs_source_selection := media_source_id.is_empty()
	var result := await api.request("/Items/%s/PlaybackInfo" % str(item.Id).uri_encode(), HTTPClient.METHOD_POST, body)
	if current != generation: return
	if not result.ok:
		failed.emit(result.error)
		return
	if result.data.get("MediaSources", []).is_empty():
		failed.emit("Jellyfin could not provide a video stream. Check your account's playback permissions.")
		return
	source = {}
	for candidate in result.data.MediaSources:
		if media_source_id.is_empty() or str(candidate.get("Id", "")) == media_source_id:
			source = candidate
			break
	if source.is_empty():
		failed.emit("The selected version is no longer available. Reopen the item and choose another version.")
		return
	media_source_id = str(source.Id)
	var resolved_video := _source_video(source)
	if not use_transcode and not original and resolved_video != video_stream \
			and _decode_support(resolved_video) == VideoBackend.DecodeSupport.UNSUPPORTED:
		await open(item, true, true)
		return
	if video_backend != null and not use_transcode and not original and video_stream.is_empty() \
			and not str(resolved_video.get("Codec", "")).is_empty():
		await open(item, false, true)
		return
	if needs_source_selection and source.get("DefaultSubtitleStreamIndex") != null and int(source.DefaultSubtitleStreamIndex) >= 0:
		await open(item, transcode, true)
		return
	session_id = result.data.get("PlaySessionId", "")
	var url: String
	var start_ms := int(position_ticks / 10000)
	if original and not source.get("SupportsDirectPlay", false):
		failed.emit("Jellyfin cannot provide the original video. Choose Transcoded in Settings > Playback.")
		return
	if source.get("SupportsDirectPlay", false) and not use_transcode and audio_index < 0:
		method = "DirectPlay"
		url = api.server + "/Videos/%s/stream" % str(item.Id).uri_encode() + api.query({"Static": "true", "MediaSourceId": source.Id})
	else:
		method = "Transcode"
		var path: String = source.get("TranscodingUrl", "")
		if path.is_empty():
			failed.emit("Jellyfin needs to convert this video but did not provide a stream.")
			return
		if not use_transcode and (source.get("SupportsDirectStream", false) or _copies_video(path)):
			method = "DirectStream"
		url = api.stream_url(path)
		if url.is_empty():
			failed.emit("The server returned an unsupported stream address.")
			return
		if not is_hls(): start_ms = 0
	stream_ready.emit(url, source, start_ms)

func is_hls() -> bool:
	if method == "DirectPlay": return false
	var protocol := str(source.get("TranscodingSubProtocol", "")).to_lower()
	var path := str(source.get("TranscodingUrl", "")).get_slice("?", 0).to_lower()
	return protocol == "hls" or path.ends_with(".m3u8")

func _selected_source(continuing: bool) -> Dictionary:
	if continuing and not source.is_empty(): return source
	var candidates: Variant = item.get("MediaSources")
	if candidates is Array:
		for candidate in candidates:
			if str(candidate.get("Id", "")) == media_source_id: return candidate
	return {}

func _source_video(candidate: Dictionary) -> Dictionary:
	var streams: Variant = candidate.get("MediaStreams")
	if streams is Array:
		for stream in streams:
			if stream.get("Type") == "Video": return stream
	return {}

func _decode_support(stream: Dictionary) -> VideoBackend.DecodeSupport:
	if video_backend == null or stream.is_empty(): return VideoBackend.DecodeSupport.UNKNOWN
	return video_backend.decode_support(stream)

func _transcode_limits() -> Dictionary:
	var preset: Dictionary = JellyXRSettings.TRANSCODE_PRESETS.get(active_transcode_resolution, JellyXRSettings.TRANSCODE_PRESETS[1080])
	var requested := {"width": preset.width, "height": preset.height, "fps": active_transcode_max_fps, "bitrate": preset.bitrate}
	if active_playback_mode != "auto" or video_backend == null: return requested
	var unverified := {}
	for height in [2160, 1440, 1080, 720]:
		if height > active_transcode_resolution: continue
		var candidate: Dictionary = JellyXRSettings.TRANSCODE_PRESETS[height]
		for fps in [active_transcode_max_fps, 30, 24]:
			if fps > active_transcode_max_fps: continue
			var stream := {"Codec": "h264", "Profile": "High", "BitDepth": 8,
				"Width": candidate.width, "Height": height, "RealFrameRate": fps}
			var support := _decode_support(stream)
			var limits := {"width": candidate.width, "height": height, "fps": fps, "bitrate": candidate.bitrate}
			if support == VideoBackend.DecodeSupport.HARDWARE: return limits
			if support == VideoBackend.DecodeSupport.UNKNOWN and unverified.is_empty(): unverified = limits
	return unverified

func _device_profile(transcode: bool, original: bool = false, selected_codec: String = "") -> Dictionary:
	var native_pc := _uses_native_pc_decoder()
	var direct_profile := {"Container": "mp4,m4v,mkv,webm", "Type": "Video"}
	if not original:
		if video_backend == null:
			direct_profile["VideoCodec"] = PC_VIDEO_CODECS if native_pc else "h264,hevc,vp9"
		elif not selected_codec.is_empty():
			direct_profile["VideoCodec"] = selected_codec
		direct_profile["AudioCodec"] = PC_AUDIO_CODECS if native_pc else "aac,mp3,opus,vorbis"
	var transcoding_profile := {"Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac", "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "2", "MinSegments": 2, "BreakOnNonKeyFrames": true}
	var codec_conditions := [{"Condition": "Equals", "Property": "VideoRangeType", "Value": "SDR", "IsRequired": true}]
	if native_pc and not transcode:
		codec_conditions = [{"Condition": "EqualsAny", "Property": "VideoRangeType", "Value": PC_VIDEO_RANGES, "IsRequired": true}]
	var preset := _transcode_limits()
	transcoding_profile["Conditions"] = []
	if not preset.is_empty():
		for limit in [["Width", preset.width], ["Height", preset.height], ["VideoFramerate", preset.fps], ["VideoBitrate", preset.bitrate]]:
			transcoding_profile.Conditions.append({"Condition": "LessThanEqual", "Property": limit[0], "Value": str(limit[1]), "IsRequired": true})
	if transcode: codec_conditions.append_array(transcoding_profile.Conditions)
	return {
		"Name": ("jellyXR original " if original else ("jellyXR native " if native_pc else "jellyXR SDR ")) + OS.get_name(),
		"MaxStreamingBitrate": 2147483647 if original or native_pc else 80000000,
		"DirectPlayProfiles": [] if transcode else [direct_profile],
		"TranscodingProfiles": [] if original or preset.is_empty() else [transcoding_profile],
		"CodecProfiles": [] if original else [{"Type": "Video", "Conditions": codec_conditions}],
		"SubtitleProfiles": [{"Format": "vtt", "Method": "External"}, {"Format": "pgssub", "Method": "Encode"}, {"Format": "dvdsub", "Method": "Encode"}, {"Format": "dvbsub", "Method": "Encode"}]
	}

func _uses_native_pc_decoder() -> bool:
	return OS.get_name() in ["Windows", "Linux"] and ClassDB.class_exists("JellyXRMpv")

func retry_transcode() -> void:
	if active_playback_mode == "original":
		failed.emit("The original video failed to play. Choose Transcoded in Settings > Playback.")
		return
	if fallback_attempted or method == "Transcode":
		failed.emit("Playback failed after Jellyfin tried to convert the video. Check the server's transcoding settings and logs.")
		return
	fallback_attempted = true
	var current := generation
	await report("Stopped")
	if current == generation: await open(item, true, true)

func report(event: String, paused: bool = false) -> void:
	if session_id.is_empty(): return
	if event == "Playing": started = true
	if not started: return
	var path := "/Sessions/Playing" + ("/" + event if event != "Playing" else "")
	var body := {"ItemId": item.Id, "MediaSourceId": source.Id, "PlaySessionId": session_id, "PositionTicks": position_ticks, "IsPaused": paused, "CanSeek": true, "PlayMethod": method, "SubtitleStreamIndex": subtitle_index}
	if audio_index >= 0:
		body["AudioStreamIndex"] = audio_index
	elif source.get("DefaultAudioStreamIndex") != null:
		body["AudioStreamIndex"] = int(source.DefaultAudioStreamIndex)
	var result := await api.request(path, HTTPClient.METHOD_POST, body)
	if not result.ok:
		var message := "Jellyfin playback report (%s) failed: %s" % [event, result.get("error", "Unknown error.")]
		push_warning(message)
		reporting_failed.emit(message)
	if event == "Stopped":
		started = false
		if method != "DirectPlay":
			await api.request("/Videos/ActiveEncodings" + api.query({"DeviceId": api.device_id, "PlaySessionId": session_id}), HTTPClient.METHOD_DELETE)

func cancel_pending() -> void:
	generation += 1

func _copies_video(path: String) -> bool:
	for pair in path.get_slice("?", 1).split("&"):
		if pair.get_slice("=", 0).to_lower() == "videocodec":
			return pair.get_slice("=", 1).uri_decode().to_lower() == "copy"
	return false
