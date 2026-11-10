class_name PcVideo
extends VideoBackend

func available() -> bool:
	return get_viewport().use_xr and ClassDB.class_exists("JellyXRMpv")

func unavailable_message() -> String:
	if not get_viewport().use_xr:
		return "Connect your headset and start an OpenXR runtime such as SteamVR to play videos. Desktop mode only shows the interface."
	if OS.get_name() == "Linux":
		return "The video plugin could not load. Extract all files from the build for your computer and install libmpv2 with your package manager."
	return "The video plugin is missing. Extract all files from the Windows build, including the DLLs."

func open(url: String, authorization: String, start_ms: int) -> void:
	_set_texture(null)
	if not available():
		failed.emit(unavailable_message())
		return
	_initialize_bridge()
	_apply_volume()
	paused = false
	var error: String = bridge.open_video(url, authorization, start_ms)
	if not error.is_empty(): failed.emit(error)

func _initialize_bridge() -> void:
	if bridge != null: return
	bridge = ClassDB.instantiate("JellyXRMpv")
	add_child(bridge)
	bridge.prepared.connect(func(): prepared.emit())
	bridge.ended.connect(func(): ended.emit())
	bridge.failed.connect(func(message: String): failed.emit(message))
	bridge.size_changed.connect(func(w: int, h: int): size_changed.emit(w, h))
	bridge.texture_changed.connect(_set_texture)

func scan_decoders() -> void:
	if not ClassDB.class_exists("JellyXRMpv"): return
	_initialize_bridge()
	if bridge.has_method("scan_decoders"): bridge.scan_decoders()

func decode_support(stream: Dictionary) -> DecodeSupport:
	if bridge == null or not bridge.has_method("decode_support"): return DecodeSupport.UNKNOWN
	return bridge.decode_support(str(stream.get("Codec", "")), str(stream.get("Profile", "")),
		int(str(stream.get("BitDepth"))), int(str(stream.get("Width"))), int(str(stream.get("Height")))) as DecodeSupport

func active_decode_support() -> DecodeSupport:
	if bridge == null or not bridge.has_method("active_decode_support"): return DecodeSupport.UNKNOWN
	return bridge.active_decode_support() as DecodeSupport

func decoder_summary() -> String:
	if bridge == null or not bridge.has_method("decoder_summary"): return super.decoder_summary()
	return bridge.decoder_summary()

func _set_texture(texture: Texture2D) -> void:
	if material == null: return
	material.set_shader_parameter("video_texture", texture)
	material.set_shader_parameter("direct_yuv", false)
	var parameters: Dictionary = {}
	if texture != null and bridge != null:
		parameters = bridge.video_shader_parameters()
	for parameter in parameters:
		material.set_shader_parameter(parameter, parameters[parameter])
	if parameters.is_empty():
		for parameter in ["y_plane", "u_plane", "v_plane"]:
			material.set_shader_parameter(parameter, null)

func toggle_pause() -> void:
	if bridge != null:
		paused = not paused
		bridge.set_paused(paused)

func seek(milliseconds: int) -> void:
	if bridge != null: bridge.seek_to(maxi(0, milliseconds))

func position_ms() -> int:
	return bridge.position_ms() if bridge != null else 0

func duration_ms() -> int:
	return bridge.duration_ms() if bridge != null else 0

func stop() -> void:
	_set_texture(null)
	if bridge != null: bridge.stop_video()
	paused = false
