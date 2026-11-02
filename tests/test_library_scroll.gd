extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail_next := false
	var total := 72

	func library(term: String = "", start: int = 0, parent: String = "") -> Dictionary:
		calls.append([term, start, parent])
		await get_tree().process_frame
		if fail_next:
			fail_next = false
			return {"ok": false, "error": "Connection failed"}
		var items: Array = []
		for index in range(start, mini(start + 12, total)):
			items.append({"Id": str(index), "Name": "Movie %d" % index, "Type": "Movie"})
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": total}}

	func folder_items(term: String = "", start: int = 0, parent: String = "") -> Dictionary:
		return await library(term, start, parent)

	func details(id: String) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true, "data": {"Id": id, "Name": "Movie", "Type": "Movie", "MediaSources": []}}

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(60): await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func load_and_scroll(view: LibraryView, position: int) -> void:
	while view.offset < 36:
		await view._more(view.generation)
	view.scroll.scroll_vertical = position
	await settle()

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.shell.content_reveal_delay = 0.0
	app.api.queue_free()
	var api := FixtureApi.new()
	app.add_child(api)
	app.api = api
	app.libraries_loaded = true
	app.shell.set_libraries([{"Id": "movies", "Name": "Movies", "CollectionType": "movies"}])
	app._open_library("movies", "Movies")
	await settle()
	var view: LibraryView = app.page.get_child(0)
	view.field.text = "movie"
	view.refresh("movie")
	await settle()
	await load_and_scroll(view, 1500)
	var saved_scroll := view.scroll.scroll_vertical
	var saved_count := view.offset
	check(saved_scroll == 1500, "The fixture scrolls beyond the first page")
	await app._details({"Id": "20", "Type": "Movie"})
	check(app.page.get_child(0) is DetailsView, "Selecting a movie opens details")
	app.shell.content_reveal_delay = 0.4
	app.page.get_child(0).back_button.pressed.emit()
	await create_timer(0.5).timeout
	await settle()
	app.shell.content_reveal_delay = 0.0
	view = app.page.get_child(0)
	check(view.search == "movie" and view.field.text == "movie", "Returning from details restores the search and its input")
	check(view.offset >= saved_count and view.scroll.scroll_vertical == saved_scroll, "Returning from details reloads the saved pages and restores the exact scroll position")
	await app._details({"Id": "20", "Type": "Movie"})
	api.fail_next = true
	app._show_library()
	await settle()
	view = app.page.get_child(0)
	view.content.get_child(0).pressed.emit()
	await settle()
	check(view.scroll.scroll_vertical == saved_scroll, "A failed return request preserves the saved position through Retry")
	view.refresh("different")
	await settle()
	check(view.scroll.scroll_vertical == 0, "A new search starts at the top")
	app._open_library("movies", "Movies")
	await settle()
	view = app.page.get_child(0)
	check(view.search.is_empty() and view.scroll.scroll_vertical == 0, "Sidebar navigation starts a fresh library visit")
	app.shell.set_libraries([{"Id": "folders", "Name": "Videos", "CollectionType": "homevideos"}])
	app._open_library("folders", "Videos")
	await settle()
	view = app.page.get_child(0)
	await load_and_scroll(view, 1300)
	var root_scroll := view.scroll.scroll_vertical
	view._chosen({"Id": "child", "Name": "Child", "Type": "Folder"})
	await settle()
	check(view.scroll.scroll_vertical == 0, "Opening an unvisited folder starts at the top")
	await load_and_scroll(view, 1700)
	var child_scroll := view.scroll.scroll_vertical
	view._chosen({"Id": "nested", "Name": "Nested", "Type": "Folder"})
	await settle()
	view.go_up()
	await settle()
	check(view.scroll.scroll_vertical == child_scroll, "Going up from a nested folder restores its parent's scroll position")
	await app._details({"Id": "20", "Type": "Movie"})
	app._show_library()
	await settle()
	view = app.page.get_child(0)
	check(view.parent_id() == "child" and view.scroll.scroll_vertical == child_scroll, "Returning from details inside a folder restores that folder and position")
	view.go_up()
	await settle()
	check(view.parent_id() == "folders" and view.scroll.scroll_vertical == root_scroll, "The library root position survives nested folders and a detail page")
	view._chosen({"Id": "child", "Name": "Child", "Type": "Folder"})
	view.refresh("new search")
	await settle()
	check(view.search == "new search" and view.scroll.scroll_vertical == 0, "A new search cancels pending scroll restoration")
	api.total = 2
	view.go_up()
	await settle()
	check(not view.busy and view.restore_scroll == -1, "A shortened library finishes restoration even when the old position no longer exists")
	app.queue_free()
	await process_frame
	print("Library scroll failures: ", failures)
	quit(1 if failures else 0)
