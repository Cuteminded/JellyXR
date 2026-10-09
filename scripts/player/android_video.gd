class_name AndroidVideo
extends Node

signal failed(message: String)
signal prepared
signal ended
signal size_changed(width: int, height: int)
var bridge: Object
var texture: ExternalTexture
var paused := false
var material: ShaderMaterial

func _ready() -> void:
	if not Engine.has_singleton("JellyframeVideo"): return
	bridge = Engine.get_singleton("JellyframeVideo")
	bridge.connect("prepared", func(): prepared.emit())
	bridge.connect("completed", func(): ended.emit())
	bridge.connect("failed", func(message: String): failed.emit(message))
	bridge.connect("video_size", func(w: int, h: int): size_changed.emit(w, h))
	texture = ExternalTexture.new()

func available() -> bool:
	return bridge != null

func open(url: String, authorization: String, start_ms: int) -> void:
	print("Jellyframe: opening video")
	if not available():
		failed.emit("Video playback requires the Android plugin. Desktop mode previews the interface only.")
		return
	material.set_shader_parameter("video_texture", texture)
	print("Jellyframe: external texture assigned")
	await RenderingServer.frame_post_draw
	print("Jellyframe: starting decoder, texture ID ", texture.get_external_texture_id())
	bridge.open_video(texture.get_external_texture_id(), url, authorization, start_ms)
	paused = false

func toggle_pause() -> void:
	if available():
		paused = not paused
		bridge.set_paused(paused)

func seek(milliseconds: int) -> void:
	if available(): bridge.seek_to(maxi(0, milliseconds))

func position_ms() -> int:
	return bridge.position_ms() if available() else 0

func stop() -> void:
	if available(): bridge.stop_video()

func _process(_delta: float) -> void:
	if not available() or material == null: return
	var matrix: PackedFloat32Array = bridge.texture_transform()
	if matrix.size() == 16:
		material.set_shader_parameter("texture_transform", Projection(Vector4(matrix[0], matrix[1], matrix[2], matrix[3]), Vector4(matrix[4], matrix[5], matrix[6], matrix[7]), Vector4(matrix[8], matrix[9], matrix[10], matrix[11]), Vector4(matrix[12], matrix[13], matrix[14], matrix[15])))
