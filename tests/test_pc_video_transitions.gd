extends SceneTree

class PreviewVideo extends PcVideo:
	func available() -> bool:
		return ClassDB.class_exists("JellyframeMpv")

var video: PcVideo
var screen: SubViewport
var material: ShaderMaterial
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run_check")

func require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	if video != null: video.stop()
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
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/pc_video.gdshader")
	mesh.material_override = material
	screen.add_child(mesh)

func screen_brightness() -> float:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := screen.get_texture().get_image()
	var brightest := 0.0
	for y in range(8, 57, 8):
		for x in range(8, 57, 8):
			brightest = maxf(brightest, image.get_pixel(x, y).get_luminance())
	return brightest

func wait_for_video() -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while material.get_shader_parameter("video_texture") == null and errors.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return require(errors.is_empty() and material.get_shader_parameter("video_texture") != null, "Video produces a texture: " + str(errors))

func run_check() -> void:
	if not require(DisplayServer.get_name() != "headless", "Screen transition checks require a graphics context"): return
	make_screen()
	video = PreviewVideo.new()
	video.material = material
	video.failed.connect(func(message: String): errors.append(message))
	root.add_child(video)
	if not require(await screen_brightness() < 0.001, "The screen is black before the first video"): return
	var url := ProjectSettings.globalize_path("res://native/android/src/main/res/raw/stereo_test.mp4")
	for cycle in range(2):
		video.open(url, "", 0)
		if not await wait_for_video(): return
		if not require(await screen_brightness() > 0.2, "The video becomes visible after opening"): return
		video.stop()
		if not require(await screen_brightness() < 0.001, "The screen returns to black after stopping"): return
	video.queue_free()
	screen.queue_free()
	await process_frame
	print("PC video black startup, stop, and reopen checks: PASS")
	quit()
