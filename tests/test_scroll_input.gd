extends SceneTree

var selections := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var feedback := MenuFeedback.new()
	root.add_child(feedback)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 960)
	root.add_child(viewport)
	var shell := UiShell.new()
	viewport.add_child(shell)
	shell.set_signed_in(true)
	var items := []
	for index in range(30): items.append({"Id": str(index), "Name": "Library %d" % index})
	shell.set_libraries(items)
	shell.navigate.connect(func(_id: String, _title: String): selections += 1)
	var pointer := PointerInput.new()
	pointer.viewport = viewport
	await process_frame
	await process_frame
	var first: Button = shell.buttons["0"]
	var point := first.get_global_rect().get_center()
	pointer.sample_trigger(0.0)
	pointer.aim(point, true)
	for index in range(20):
		pointer.scroll(point, -0.2)
		await process_frame
	point = shell.home.get_global_rect().get_center()
	pointer.aim(point, true)
	pointer.sample_trigger(0.8)
	pointer.aim(point, true)
	pointer.sample_trigger(0.0)
	pointer.aim(point, true)
	print("Home activations after scrolling: ", selections)
	pointer.cancel()
	var artwork := ArtworkLoader.new()
	root.add_child(artwork)
	var cast := CastCarousel.new()
	cast.artwork = artwork
	cast.position = Vector2(300, 200)
	cast.size = Vector2(800, 400)
	for index in range(12): cast.people.append({"Name": "Actor %d" % index})
	viewport.add_child(cast)
	await process_frame
	await process_frame
	point = cast.scroll.get_global_rect().position + Vector2(90, 90)
	pointer.aim(point, true)
	pointer.scroll(point, 0.2, true)
	await process_frame
	assert(cast.scroll.scroll_horizontal > 0, "Right joystick input must reach the cast carousel.")
	pointer.scroll(point, -0.2, true)
	await process_frame
	assert(cast.scroll.scroll_horizontal == 0, "Left joystick input must move the cast carousel back.")
	pointer.cancel()
	cast.queue_free()
	shell.queue_free()
	await process_frame
	await check_screen_sliders(viewport, pointer)
	feedback.player.stop()
	quit(0 if selections == 1 else 1)

func check_screen_sliders(viewport: SubViewport, pointer: PointerInput) -> void:
	var scroller := ScrollContainer.new()
	scroller.size = Vector2(800, 400)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport.add_child(scroller)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(700, 1200)
	scroller.add_child(body)
	var slider := preload("res://scripts/ui/screen_position_slider.gd").new()
	slider.custom_minimum_size = Vector2(600, 48)
	slider.min_value = 1.5
	slider.max_value = 7.0
	slider.step = 0.05
	slider.value = 3.5
	body.add_child(slider)
	await process_frame
	await process_frame
	var point := slider.get_global_rect().get_center()
	pointer.aim(point, true)
	for index in range(5): pointer.scroll(point, 0.2, true)
	assert(is_equal_approx(slider.value, 3.55), "Right adjusts the hovered screen slider by one step.")
	for index in range(5): pointer.scroll(point, -0.2, true)
	assert(is_equal_approx(slider.value, 3.5), "Left reduces the hovered screen slider.")
	assert(scroller.scroll_vertical == 0, "Horizontal slider input must not scroll vertically.")
	slider.grab_focus()
	pointer.scroll(point, -0.2)
	assert(is_equal_approx(slider.value, 3.5), "Down must not change even a focused slider.")
	assert(scroller.scroll_vertical > 0, "Down over a slider must scroll the page.")
	pointer.scroll(point, 0.2)
	assert(is_equal_approx(slider.value, 3.5), "Up must not change a slider.")
	assert(scroller.scroll_vertical == 0, "Up over a slider must scroll the page back.")
	slider.editable = false
	for index in range(10): pointer.scroll(point, 0.2, true)
	assert(is_equal_approx(slider.value, 3.5), "Disabled sliders must ignore horizontal input.")
	point = Vector2(300, 200)
	pointer.aim(point, true)
	for index in range(10): pointer.scroll(point, 0.2, true)
	assert(scroller.scroll_vertical == 0, "Horizontal input over a vertical page must not scroll down.")
	pointer.scroll(point, -0.2)
	var vertical_position := scroller.scroll_vertical
	assert(vertical_position > 0, "Vertical input still scrolls the page.")
	for index in range(10): pointer.scroll(point, -0.2, true)
	assert(scroller.scroll_vertical == vertical_position, "Left must not scroll a vertical page up.")
	pointer.cancel()
