extends SceneTree

class PreviewVideo extends AndroidVideo:
	func _ready() -> void:
		pass

class FixtureBridge extends RefCounted:
	var ready := true
	var opened: Array[String] = []

	func open_video(_texture_id: int, url: String, _authorization: String, _start_ms: int) -> void:
		opened.append(url)
		ready = false

	func stop_video() -> void:
		pass

	func has_video_frame() -> bool:
		return ready

	func texture_transform() -> PackedFloat32Array:
		return PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

var video: AndroidVideo
var bridge: FixtureBridge
var material: ShaderMaterial
var old_frame: ImageTexture
var screen: SubViewport

func _initialize() -> void:
	call_deferred("run_check")

func require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func make_screen() -> void:
	screen = SubViewport.new()
	screen.size = Vector2i(64, 64)
	screen.own_world_3d = true
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(screen)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 1.0
	screen.add_child(camera)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh.mesh = quad
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://shaders/video.gdshader").replace("samplerExternalOES", "sampler2D")
	material = ShaderMaterial.new()
	material.shader = shader
	mesh.material_override = material
	screen.add_child(mesh)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	old_frame = ImageTexture.create_from_image(image)
	material.set_shader_parameter("video_texture", old_frame)

func brightness() -> float:
	await process_frame
	await RenderingServer.frame_post_draw
	return screen.get_texture().get_image().get_pixel(32, 32).get_luminance()

func run_check() -> void:
	if not require(DisplayServer.get_name() != "headless", "Android transition rendering needs a graphics context"): return
	make_screen()
	video = PreviewVideo.new()
	bridge = FixtureBridge.new()
	video.bridge = bridge
	video.texture = ExternalTexture.new()
	video.material = material
	root.add_child(video)
	if not require(await brightness() < 0.001, "An old texture is black before a video opens"): return
	for url in ["first", "second"]:
		await video.open(url, "", 0)
		material.set_shader_parameter("video_texture", old_frame)
		if not require(await brightness() < 0.001, "The old picture stays hidden while the new video prepares"): return
		bridge.ready = true
		if not require(await brightness() > 0.1, "A latched first frame makes the video visible"): return
		video.stop()
		if not require(await brightness() < 0.001, "Stopping hides the frame before the asynchronous decoder releases it"): return
	var calls_before := bridge.opened.size()
	video.open("cancelled", "", 0)
	video.stop()
	await RenderingServer.frame_post_draw
	await process_frame
	if not require(bridge.opened.size() == calls_before, "Stopping cancels an open waiting for the render frame"): return
	video.open("outdated", "", 0)
	video.open("latest", "", 0)
	await RenderingServer.frame_post_draw
	await process_frame
	if not require(bridge.opened.size() == calls_before + 1 and bridge.opened.back() == "latest", "Rapid switching opens only the latest requested video"): return
	video.stop()
	video.queue_free()
	screen.queue_free()
	await process_frame
	print("Android black startup, stop, switching, and cancelled-open checks: PASS")
	quit()
