extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail_next := false
	var empty_next := false
	var total := 72
	var batch_size := 24

	func library(term: String = "", start: int = 0, _parent: String = "") -> Dictionary:
		calls.append([term, start])
		await get_tree().process_frame
		if fail_next:
			fail_next = false
			return {"ok": false, "error": "Connection failed"}
		var items := []
		if not empty_next:
			for index in range(start, mini(start + batch_size, total)):
				items.append({"Id": str(index), "Name": "Movie %d" % index, "ImageTags": {}})
		empty_next = false
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": total}}

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(12):
		await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	root.add_child(viewport)
	var api := FixtureApi.new()
	root.add_child(api)
	var library := LibraryView.new()
	library.api = api
	library.library_id = "movies"
	library.size = Vector2(1200, 600)
	viewport.add_child(library)
	await settle()
	check(api.calls == [["", 0]], "Only the first page should load while far from the bottom.")
	var bar := library.scroll.get_v_scroll_bar()
	bar.value = bar.max_value - bar.page - 200
	for index in range(5): library._check_more()
	await settle()
	check(api.calls == [["", 0], ["", 24]], "Approaching the bottom must request the next page exactly once.")
	check(library.offset == 48, "The next page must append its titles.")
	check(library.grid.get_child_count() == 48, "All pages must append to the same poster grid.")
	var previous_card: Control = library.grid.get_child(23)
	var next_card: Control = library.grid.get_child(24)
	check(is_equal_approx(previous_card.position.y, next_card.position.y), "The next page must fill the empty slot in the previous page's last row.")
	api.fail_next = true
	bar.value = bar.max_value - bar.page
	await settle()
	check(api.calls.size() == 3 and library.offset == 48, "A failed page must stop automatic retries and preserve titles.")
	var retry: Button = library.content.get_child(library.content.get_child_count() - 1)
	check(retry.text == "Retry", "A failed page must offer Retry.")
	retry.pressed.emit()
	await settle()
	check(library.offset == 72 and not library.has_more, "Retry must append the final page and stop pagination.")
	bar.value = bar.max_value - bar.page
	await settle()
	check(api.calls.size() == 4, "Scrolling past the final page must not request another page.")
	library.refresh("old")
	library.refresh("new")
	await settle()
	check(library.search == "new" and library.offset == 24, "Search must discard stale responses and reset pagination.")
	check(library.grid.get_child_count() == 24, "Search must replace the old poster grid.")
	check(bar.value == 0, "Search must reset the scroll position.")
	api.empty_next = true
	bar.value = bar.max_value - bar.page
	await settle()
	check(library.offset == 24 and not library.has_more, "An empty page must stop pagination even if the server reports more titles.")
	api.total = 3
	api.batch_size = 1
	var calls_before := api.calls.size()
	library.refresh("short")
	await settle()
	check(library.offset == 3 and not library.has_more, "Pages that do not fill the viewport must load automatically until the final page.")
	check(api.calls.size() == calls_before + 3, "A short library must request each page once.")
	print("Library pagination failures: ", failures)
	quit(1 if failures else 0)
