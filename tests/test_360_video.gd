extends SceneTree

class FixtureVideo extends VideoBackend:
	func open(_url: String, _authorization: String, _start_ms: int) -> void: pass
	func stop() -> void: pass

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	for filename in ["Beach.360.mp4", "Beach_VR360_TB.mkv", "Beach-360deg.mp4"]:
		check(VideoProjection.detect({"Path": filename}) == VideoProjection.Mode.EQUIRECTANGULAR, "360 filename marker: " + filename)
	for filename in ["/360/Beach.mp4", "Beach.3600.mp4", "Beach.mp4", "Beach.180.mp4"]:
		check(VideoProjection.detect({"Path": filename}) == VideoProjection.Mode.SCREEN, "Avoid ambiguous projection detection: " + filename)
	check(Stereo.detect({"Path": "Beach.360.TB.mp4"}) == Stereo.Mode.TOP_BOTTOM, "Top-bottom filename detection")
	check(Stereo.detect({"Video3DFormat": "FullTopAndBottom"}) == Stereo.Mode.TOP_BOTTOM, "Top-bottom metadata detection")
	check(is_equal_approx(Stereo.aspect(3840, 3840, Stereo.Mode.TOP_BOTTOM), 2.0), "Top-bottom preserves each eye's proportions")
	var mesh := VideoProjection.sphere()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		if not is_equal_approx(vertices[index].length(), 50.0):
			check(false, "Sphere vertices stay at the panorama radius")
			break
		if vertices[index].dot(normals[index]) >= 0.0:
			check(false, "Sphere normals face the viewer inside")
			break
		if uvs[index].is_equal_approx(Vector2(0.5, 0.5)):
			check(vertices[index].is_equal_approx(Vector3(0, 0, -50)), "The image center faces forward")
		if is_zero_approx(uvs[index].y):
			check(is_equal_approx(vertices[index].y, 50.0), "The top of the image is overhead")
		if is_equal_approx(uvs[index].x, 0.0) or is_equal_approx(uvs[index].x, 1.0):
			check(vertices[index].z >= -0.001, "The texture seam is behind the viewer")

	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.video.queue_free()
	var video := FixtureVideo.new()
	app.add_child(video)
	app.video = video
	app.settings.environment = "Theatre"
	app._change_environment()
	app.screen.show()
	app._select_projection(VideoProjection.Mode.EQUIRECTANGULAR)
	check(app.world.panorama.visible and app.screen.mesh == null, "360 uses the sphere instead of the screen")
	check(not app.theatre.visible, "The cinema cannot obscure the panorama")
	check(app.settings.environment == "Theatre", "360 preserves the preferred environment")
	check(app.world.panorama.global_position.is_equal_approx(app.camera.global_position), "The viewer starts at the sphere center")
	check(app.screen.global_position.is_equal_approx(app.camera.global_position - app.camera.global_basis.z * 3.0), "Controls stay in front of the viewer")
	app.camera.position += Vector3(0.3, 0.1, 0.2)
	app.camera.rotation = Vector3(0.2, 0.7, 0.1)
	app._recenter()
	check(is_zero_approx(app.world.panorama.global_rotation.x) and is_zero_approx(app.world.panorama.global_rotation.z), "Recenter preserves a level panorama horizon")
	check(is_equal_approx(app.world.panorama.global_rotation.y, app.camera.global_rotation.y), "Recenter sets the forward direction")
	var panorama_basis: Basis = app.world.panorama.global_basis
	app.camera.rotate_y(0.4)
	app.camera.position.x += 0.5
	app.world._process(0.0)
	check(app.world.panorama.global_basis.is_equal_approx(panorama_basis), "Looking around does not rotate the panorama")
	check(app.world.panorama.global_position.is_equal_approx(app.camera.global_position), "Translation keeps the viewer at the center")
	app._select_stereo(Stereo.Mode.TOP_BOTTOM)
	check(app.material.get_shader_parameter("stereo") == true and app.material.get_shader_parameter("top_bottom") == true, "Top-bottom 360 enables per-eye sampling")
	app._screen_settings()
	var view: SettingsView = app.page.get_child(0)
	check(view.projection_mode == VideoProjection.Mode.EQUIRECTANGULAR, "Settings show the active projection")
	for row in view.screen_dimensions.get_children():
		check(not row.get_child(1).editable, "Screen sliders are disabled for 360")
	app._show_playback()
	check(app.player_overlay.is_visible_in_tree(), "Playback controls remain visible in 360 mode")
	app.seeking = true
	await app._play_stream("", {"Path": "Normal.mp4"}, 0)
	check(app.projection_mode == VideoProjection.Mode.EQUIRECTANGULAR, "Transcode seeking preserves the projection override")
	app.seeking = false
	await app._play_stream("", {"Path": "Normal.mp4"}, 0)
	check(app.world.panoramic and app.mode == Stereo.Mode.TOP_BOTTOM, "Decoder fallback preserves manual projection and stereo choices")
	app.screen.hide()
	app.world._process(0.0)
	check(not app.world.panorama.visible and app.theatre.visible, "Stopping hides the panorama and restores the environment")
	app.screen.show()
	app._select_projection(VideoProjection.Mode.SCREEN)
	check(not app.world.panorama.visible and app.screen.mesh != null and app.theatre.visible, "Screen mode restores cinema playback")
	app.projection_overridden = false
	app.stereo_overridden = false
	await app._play_stream("", {"Path": "Beach.360.mp4"}, 0)
	check(app.world.panoramic and app.screen.mesh == null, "Stream opening applies automatic 360 detection")
	await app._play_stream("", {"Path": "Normal.mp4"}, 0)
	check(not app.world.panoramic and app.screen.mesh != null, "An ordinary stream returns to screen mode")
	app.playing = false
	app.queue_free()
	await process_frame
	print("360 video checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
