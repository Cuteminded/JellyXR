class_name AndroidVideo
extends VideoBackend

var texture: ExternalTexture
var playback_generation := 0
var stream_open := false
var frame_visible := false
var volume_poll_elapsed := 0.0
var unmuted_volume := 1.0

func _ready() -> void:
	if not Engine.has_singleton("JellyXRVideo"): return
	bridge = Engine.get_singleton("JellyXRVideo")
	_sync_system_volume()
	bridge.connect("prepared", func(): prepared.emit())
	bridge.connect("completed", func(): ended.emit())
	bridge.connect("failed", func(message: String): failed.emit(message))
	bridge.connect("video_size", func(w: int, h: int): size_changed.emit(w, h))
	texture = ExternalTexture.new()

func available() -> bool:
	return bridge != null

func _has_system_volume() -> bool:
	if bridge == null: return false
	if bridge.has_method("has_java_method"):
		return bridge.has_java_method("get_system_volume") and bridge.has_java_method("set_system_volume")
	return bridge.has_method("get_system_volume") and bridge.has_method("set_system_volume")

func _update_system_volume(level: float, force_emit := false) -> void:
	level = clampf(level, 0.0, 1.0)
	var silent := level <= 0.0
	if not force_emit and is_equal_approx(volume, level) and muted == silent: return
	volume = level
	muted = silent
	if volume > 0.0: unmuted_volume = volume
	volume_changed.emit(volume, muted)

func _sync_system_volume() -> void:
	if _has_system_volume(): _update_system_volume(bridge.get_system_volume())

func set_volume(level: float) -> void:
	if not _has_system_volume():
		super.set_volume(level)
		return
	_update_system_volume(bridge.set_system_volume(clampf(level, 0.0, 1.0)), true)

func toggle_mute() -> void:
	if not _has_system_volume():
		super.toggle_mute()
		return
	_sync_system_volume()
	set_volume(unmuted_volume if muted else 0.0)

func _apply_volume() -> void:
	if _has_system_volume():
		_sync_system_volume()
	else:
		super._apply_volume()

func has_android_services() -> bool:
	return available()

func unavailable_message() -> String:
	return "Video playback requires the jellyXR Android plugin."

func open(url: String, authorization: String, start_ms: int) -> void:
	playback_generation += 1
	var opening := playback_generation
	_clear_frame()
	if not available():
		failed.emit(unavailable_message())
		return
	material.set_shader_parameter("video_texture", texture)
	await RenderingServer.frame_post_draw
	if opening != playback_generation: return
	_apply_volume()
	bridge.open_video(texture.get_external_texture_id(), url, authorization, start_ms)
	stream_open = true
	paused = false

func _clear_frame() -> void:
	stream_open = false
	frame_visible = false
	if material != null: material.set_shader_parameter("video_ready", false)

func toggle_pause() -> void:
	if available():
		paused = not paused
		bridge.set_paused(paused)

func seek(milliseconds: int) -> void:
	if available(): bridge.seek_to(maxi(0, milliseconds))

func position_ms() -> int:
	return bridge.position_ms() if available() else 0

func duration_ms() -> int:
	return bridge.duration_ms() if available() else 0

func buffered_position_ms() -> int:
	return bridge.buffered_position_ms() if available() else -1

func is_buffering() -> bool:
	return bridge.is_buffering() if available() else false

func stop() -> void:
	playback_generation += 1
	_clear_frame()
	if available(): bridge.stop_video()

func _process(delta: float) -> void:
	volume_poll_elapsed += delta
	if volume_poll_elapsed >= 0.25:
		volume_poll_elapsed = 0.0
		_sync_system_volume()
	if not available() or material == null: return
	var ready: bool = stream_open and bridge.has_video_frame()
	if ready != frame_visible:
		frame_visible = ready
		material.set_shader_parameter("video_ready", ready)
	var matrix: PackedFloat32Array = bridge.texture_transform()
	if matrix.size() == 16:
		material.set_shader_parameter("texture_transform", Projection(Vector4(matrix[0], matrix[1], matrix[2], matrix[3]), Vector4(matrix[4], matrix[5], matrix[6], matrix[7]), Vector4(matrix[8], matrix[9], matrix[10], matrix[11]), Vector4(matrix[12], matrix[13], matrix[14], matrix[15])))
