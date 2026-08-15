extends SceneTree

class FixtureApi extends JellyfinClient:
	func resume_items() -> Dictionary:
		return {"ok": true, "data": {"Items": []}}
	func library(_search: String = "", _offset: int = 0, _parent_id: String = "") -> Dictionary:
		var items := []
		for index in range(20):
			items.append({"Id": str(index), "Name": "Movie %d" % index, "ImageTags": {}})
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": 20}}

var selections := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var feedback := MenuFeedback.new()
	root.add_child(feedback)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	root.add_child(viewport)
	var api := FixtureApi.new()
	root.add_child(api)
	var library := LibraryView.new()
	library.api = api
	library.size = Vector2(1200, 600)
	library.position = Vector2(32, 160)
	library.selected.connect(func(_item: Dictionary): selections += 1)
	viewport.add_child(library)
	await process_frame
	await process_frame
	var card: Button = library.content.get_child(2).get_child(0)
	var scroll: ScrollContainer = library.content.get_parent()
	scroll.ensure_control_visible(card)
	await process_frame
	var center := card.get_global_rect().get_center()
	for movement in [0.0, 4.0, 20.0]:
		selections = 0
		var motion := InputEventMouseMotion.new()
		motion.position = center
		viewport.push_input(motion, true)
		var press := InputEventMouseButton.new()
		press.position = center
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		viewport.push_input(press, true)
		motion = InputEventMouseMotion.new()
		motion.position = center + Vector2(0, movement)
		motion.relative = Vector2(0, movement)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion, true)
		var release := InputEventMouseButton.new()
		release.position = motion.position
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		viewport.push_input(release, true)
		await process_frame
		print("Poster click with %s px movement: %d selections" % [movement, selections])
		if selections != 1:
			failures += 1
			push_error("A poster click must select exactly one item.")
	feedback.player.stop()
	await process_frame
	quit(1 if failures else 0)
