extends SceneTree

class FixtureView extends PhotoView:
	func _load() -> void:
		pass

class SequenceApi extends JellyfinClient:
	var calls: Array = []
	func library(term: String = "", start: int = 0, parent: String = "") -> Dictionary:
		calls.append([term, start, parent])
		return {"ok": true, "data": {"Items": [{"Id": "video", "Type": "Video"}] if start == 25 else [{"Id": "next", "Type": "Photo"}], "TotalRecordCount": 27}}

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var sequence := PhotoSequence.new()
	sequence.items = [{"Id": "first", "Type": "Photo"}]
	sequence.index = 0
	sequence.offset = 25
	sequence.has_more = true
	sequence.search = "holiday"
	sequence.library_id = "album"
	var sequence_api := SequenceApi.new()
	root.add_child(sequence_api)
	var next := await sequence.step(1, sequence_api)
	assert(next.item.Id == "next" and not sequence.can_next())
	assert(sequence_api.calls == [["holiday", 25, "album"], ["holiday", 26, "album"]])
	var previous := await sequence.step(-1, sequence_api)
	assert(previous.item.Id == "first")
	assert((await sequence.step(-1, sequence_api)).is_empty())
	sequence_api.free()
	var view := FixtureView.new()
	view.item = {"Id": "photo", "Name": "Portrait", "Type": "Photo"}
	root.add_child(view)
	var textures: Array[Texture2D] = []
	var errors: Array[String] = []
	view.photo_ready.connect(func(texture: Texture2D): textures.append(texture))
	view.failed.connect(func(message: String): errors.append(message))
	var image := Image.create(40, 80, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	view._loaded(HTTPRequest.RESULT_SUCCESS, 200, [], image.save_jpg_to_buffer())
	assert(textures[0].get_size() == Vector2(40, 80))
	assert(errors.is_empty())
	view._loaded(HTTPRequest.RESULT_SUCCESS, 403, [], [])
	assert("403" in errors[0])
	view._loaded(HTTPRequest.RESULT_CANT_CONNECT, 0, [], [])
	assert(errors.size() == 2)
	view.free()
	assert(PhotoView.stereo_mode({"Name": "Holiday.SBS.jpg"}) == Stereo.Mode.FULL_SBS)
	assert(PhotoView.stereo_mode({"Name": "Holiday.HSBS.jpg"}) == Stereo.Mode.HALF_SBS)
	assert(PhotoView.stereo_mode({"Name": "Holiday.TB.jpg"}) == Stereo.Mode.TOP_BOTTOM)
	assert(PhotoView.stereo_mode({"Name": "Holiday.jpg"}) == Stereo.Mode.MONO)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	var original: ShaderMaterial = app.material
	app.api.server = "http://127.0.0.1:18964"
	var previous_page: Array = app.page.get_children()
	app.panel.show()
	app.keyboard.show()
	await app._show_photo({"Id": "photo", "Name": "Holiday.SBS.jpg", "Type": "Photo"})
	assert(not app.panel.visible and not app.keyboard.visible, "Opening a photo hides the library and keyboard before loading finishes")
	var indicator: PlayerLoading = app.world.player_loading
	assert(indicator.is_visible_in_tree(), "Photo loading is visible while the image request is pending")
	assert(indicator.label.text == "Loading photo...")
	app._process(0.01)
	assert(indicator.is_visible_in_tree(), "Frame updates preserve photo loading feedback")
	assert(app.page.get_children() == previous_page, "Photos preserve the library instead of opening a preview page")
	var texture := ImageTexture.create_from_image(image)
	var screen_transform: Transform3D = app.screen.global_transform
	var theatre_transform: Transform3D = app.theatre.global_transform
	app.camera.position += Vector3(0.5, 0.2, 0.3)
	app.camera.rotation.y += 0.6
	app._photo_ready(texture)
	assert(not indicator.visible, "A ready photo clears loading feedback")
	assert(app.screen.global_transform.is_equal_approx(screen_transform), "Opening a photo preserves screen placement after head movement")
	assert(app.theatre.global_transform.is_equal_approx(theatre_transform), "Opening a photo does not recenter the theatre")
	assert(app.photo_active and not app.playing)
	assert(app.screen.visible and app.screen.material_override == app.material)
	assert(app.world.panorama.material_override == app.material)
	assert(app.material.get_shader_parameter("video_texture") == texture)
	assert(app.material.get_shader_parameter("stereo") == true)
	assert(app.mode == Stereo.Mode.FULL_SBS)
	assert(not app.player_overlay.timeline.visible and not app.player_overlay.pause_button.visible)
	app._select_stereo(Stereo.Mode.TOP_BOTTOM)
	assert(app.material.get_shader_parameter("top_bottom") == true)
	app._select_projection(VideoProjection.Mode.EQUIRECTANGULAR)
	assert(app.world.panoramic)
	await app._stop(false)
	assert(not app.photo_active and not app.screen.visible)
	assert(app.material == original and app.screen.material_override == original)
	assert(app.world.panorama.material_override == original and not app.world.panoramic)
	assert(app.player_overlay.timeline.visible and app.player_overlay.pause_button.visible)
	await app._show_photo({"Id": "pending", "Name": "Pending", "Type": "Photo"})
	assert(indicator.is_visible_in_tree())
	app._photo_failed("Test failure")
	assert(app.panel.visible, "A failed photo returns to the library")
	assert(not indicator.visible and not app.photo_loading, "Failed photos clear loading feedback")
	await app._show_photo({"Id": "cancelled", "Name": "Cancelled", "Type": "Photo"})
	await app._stop(false)
	assert(not indicator.visible and not app.photo_loading, "Stopping a pending photo clears loading feedback")
	app.free()
	print("Photo viewer checks: PASS")
	quit()
