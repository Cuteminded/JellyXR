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
	var driver := RenderingServer.get_current_rendering_driver_name()
	var renderer: String = {
		"vulkan": "Vulkan",
		"opengl3": "OpenGL", 
		"opengl3_es": "OpenGL", 
		"d3d11": "Direct3D 11",
		"d3d12": "Direct3D 12"
		}.get(driver, driver)
	return {
		"Playback resolution": "%d x %d" % [playback_size.x, playback_size.y] if playback_size.x > 0 and playback_size.y > 0 else "N/A",
		"Playback": session.method,
		"Source video": "%d x %d / %.3f fps" % [width, height, fps] if width > 0 else "N/A",
		"Source codec": str(stream.get("Codec", "N/A")).to_upper(),
		"Source bitrate": "%.2f Mbps" % (bitrate / 1000000.0) if bitrate > 0 else "N/A",
		"Renderer / FPS": "%s / %d" % [renderer, Engine.get_frames_per_second()],
		"Player state": "Buffering" if video.is_buffering() else ("Paused" if video.paused else "Playing"),
		"Video decoder": str(diagnostics.get("codec", "Platform decoder")),
		"Hardware decoding": _hardware_decoder(diagnostics),
		"Dropped frames": str(diagnostics.get("dropped_frames", "N/A")),
		"Read ahead": "%.2f s" % (float(diagnostics.read_ahead_ms) / 1000.0) if diagnostics.has("read_ahead_ms") else "0",
	}

static func _hardware_decoder(diagnostics: Dictionary) -> String:
	if diagnostics.get("d3d12_gpu_copy", false): return "D3D12VA"
	if diagnostics.get("d3d11_gpu_copy", false): return "D3D11VA"
	if diagnostics.get("vaapi_gpu_copy", false): return "VAAPI"
	return str(diagnostics.get("hardware_device", "N/A"))
