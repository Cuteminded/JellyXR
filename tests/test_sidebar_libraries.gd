extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	var items: Array = []
	for kind in ["movies", "tvshows", "homevideos", "mixed", "music", "musicvideos", "photos", "books", "livetv", "playlists", "boxsets", "future-type"]:
		items.append({"Id": kind, "Name": kind.capitalize(), "CollectionType": kind})
	items.append({"Id": "missing", "Name": "Mixed library"})
	items.append({"Id": "null", "Name": "Mixed with null type", "CollectionType": null})
	shell.set_libraries(items)
	assert(shell.buttons.size() == 6, "Only supported video libraries and untyped mixed libraries are shown")
	for id in ["movies", "tvshows", "homevideos", "mixed", "missing", "null"]:
		assert(shell.buttons.has(id))
		assert(shell.buttons[id].icon != null, "Each library has a leading icon")
		assert("assets/icons/material/" in shell.buttons[id].icon.resource_path, "Each library uses a Material Symbols icon")
	var selected: Array = []
	shell.navigate.connect(func(id: String, title: String): selected.append([id, title]))
	shell.buttons["movies"].pressed.emit()
	assert(selected == [["movies", "Movies"]], "Library navigation preserves the server ID and title")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/sidebar-preview.png")
	shell.set_libraries([{"Id": "music", "CollectionType": "music"}])
	assert(shell.buttons.is_empty())
	assert(shell.libraries.get_child(0).text == "No supported libraries")
	print("Sidebar library checks: PASS")
	quit()
