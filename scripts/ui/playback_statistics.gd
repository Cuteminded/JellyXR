extends RefCounted

static func snapshot(session: PlaybackSession, video: VideoBackend, playback_size := Vector2i.ZERO) -> Dictionary:
	var stream: Dictionary = {}
	for candidate in session.source.get("MediaStreams", []):
		if candidate.get("Type") == "Video":
			stream = candidate
			break
	var diagnostics: Dictionary = {}
	if video.bridge != null and video.bridge.has_method("playback_diagnostics"):
		diagnostics = video.bridge.playback_diagnostics()
	var width := int(stream.get("Width", 0))
	var height := int(stream.get("Height", 0))
	var fps := float(stream.get("AverageFrameRate", stream.get("RealFrameRate", 0.0)))
	var bitrate := int(session.source.get("Bitrate", 0))
	return {
		"Playback resolution": "%d x %d" % [playback_size.x, playback_size.y] if playback_size.x > 0 and playback_size.y > 0 else "Not reported",
		"Playback": session.method,
		"Source video": "%d x %d / %.3f fps" % [width, height, fps] if width > 0 else "Not reported",
		"Source codec": str(stream.get("Codec", "Not reported")).to_upper(),
		"Source bitrate": "%.2f Mbps" % (bitrate / 1000000.0) if bitrate > 0 else "Not reported",
		"Renderer / app FPS": "%s / %d" % [RenderingServer.get_current_rendering_method(), Engine.get_frames_per_second()],
		"Player state": "Buffering" if video.is_buffering() else ("Paused" if video.paused else "Playing"),
		"Video decoder": str(diagnostics.get("codec", "Platform decoder")),
		"Hardware decoding": str(diagnostics.get("hardware_device", "Not reported")),
		"Dropped frames": str(diagnostics.get("dropped_frames", "Not reported")),
		"Read ahead": "%.2f s" % (float(diagnostics.read_ahead_ms) / 1000.0) if diagnostics.has("read_ahead_ms") else "Not reported",
	}
