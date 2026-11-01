extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail_next := false
	var wait_next := false
	signal release_request

	func folder_items(term: String = "", start: int = 0, parent: String = "") -> Dictionary:
		calls.append([term, start, parent])
		if wait_next:
			wait_next = false
			await release_request
		else:
			await get_tree().process_frame
		if fail_next:
			fail_next = false
			return {"ok": false, "error": "Connection failed"}
		var items: Array = []
		match parent:
			"library": items = [{"Id": "folder", "Name": "Trips", "Type": "Folder"}, {"Id": "root-video", "Type": "Video"}]
			"folder": items = [{"Id": "album", "Name": "Mountains", "Type": "PhotoAlbum"}, {"Id": "song", "Type": "MusicVideo"}]
			"album":
				items = [{"Id": "photo", "Type": "Photo"}] if start == 0 else [{"Id": "next-photo", "Type": "Photo"}]
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": 2}}

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(12): await process_frame

func run_checks() -> void:
	var api := FixtureApi.new()
	root.add_child(api)
	var view := LibraryView.new()
	view.api = api
	view.library_id = "library"
	view.library_name = "Home videos"
	view.folder_mode = true
	view.size = Vector2(1200, 600)
	root.add_child(view)
	var selected: Array = []
	view.selected.connect(func(item: Dictionary): selected.append(item))
	await settle()
	assert(api.calls == [["", 0, "library"]])
	assert(view.up_button.disabled and view.path_label.text == "Home videos")
	assert(view.content.get_child(0) is Label, "Folder browsing has no random video hero")
	view.grid.get_child(0).pressed.emit()
	await settle()
	assert(selected.is_empty(), "Folders open without requesting video details")
	assert(api.calls.back() == ["", 0, "folder"])
	assert(view.path_label.text == "Home videos / Trips" and not view.up_button.disabled)
	view.grid.get_child(1).pressed.emit()
	assert(selected.back().Id == "song", "Music videos still open their details")
	view.grid.get_child(0).pressed.emit()
	await settle()
	assert(view.path_label.text == "Home videos / Trips / Mountains")
	var sequence := PhotoSequence.new()
	sequence.capture(view, view.grid.get_child(0).item)
	assert(sequence.folder_mode and sequence.library_id == "album")
	sequence.items = [sequence.items[0]]
	sequence.offset = 1
	sequence.has_more = true
	assert((await sequence.step(1, api)).item.Id == "next-photo")
	assert(api.calls.back() == ["", 1, "album"], "Photo pagination stays in the selected album")
	view.refresh("holiday")
	await settle()
	assert(api.calls.has(["holiday", 0, "album"]))
	view.go_up()
	await settle()
	assert(view.search.is_empty() and view.field.text.is_empty())
	assert(api.calls.back() == ["", 0, "folder"])
	api.fail_next = true
	view.refresh()
	await settle()
	assert(view.content.get_child(0).text == "Retry")
	view.content.get_child(0).pressed.emit()
	await settle()
	assert(view.grid.get_child_count() == 2 and view.parent_id() == "folder")
	api.wait_next = true
	view.refresh("stale")
	view.go_up()
	await settle()
	api.release_request.emit()
	await settle()
	assert(view.parent_id() == "library" and view.grid.get_child(0).item.Id == "folder", "A stale folder response cannot replace the current directory")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/folder-navigation.png")
	view.free()
	api.free()
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.libraries_loaded = true
	app.api.server = "http://127.0.0.1:18964"
	app.shell.set_libraries([{"Id": "library", "Name": "Music videos", "CollectionType": "musicvideos"}])
	var path := [{"Id": "folder", "Name": "Trips", "Type": "Folder"}]
	app._open_library("library", "Music videos", path)
	assert(app.page.get_child(0).folder_mode and app.page.get_child(0).parent_id() == "folder")
	app._show_library()
	assert(app.page.get_child(0).parent_id() == "folder", "Returning from details or playback preserves the directory")
	app._open_library("library", "Music videos")
	assert(app.page.get_child(0).parent_id() == "library", "Sidebar navigation opens the library root")
	app.free()
	print("Library folder checks: PASS")
	quit()
