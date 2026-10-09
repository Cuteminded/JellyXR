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
	feedback.player.stop()
	quit(0 if selections == 1 else 1)
