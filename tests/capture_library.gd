extends SceneTree

class FixtureApi extends JellyfinClient:
	func resume_items() -> Dictionary:
		return {"ok": true, "data": {"Items": []}}
	func library(_term: String = "", _offset: int = 0, _parent: String = "") -> Dictionary:
		var items := []
		for title in ["The long way home", "Northern lights", "Beyond the horizon", "The last voyage", "Wild coast", "A quiet place"]:
			items.append({"Id": title, "Name": title, "ProductionYear": 2025, "Type": "Movie", "Overview": "A journey through unfamiliar places, and the people who make them feel like home.", "ImageTags": {}})
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": items.size()}}

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	shell.select("", "Home")
	shell.set_libraries([{"Id": "movies", "Name": "Movies"}, {"Id": "tv", "Name": "TV shows"}, {"Id": "3d", "Name": "3D movies"}])
	var api := FixtureApi.new()
	root.add_child(api)
	var library := LibraryView.new()
	library.api = api
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.status.connect(func(message: String): shell.status.text = message)
	shell.page.add_child(library)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/library-preview.png")
	quit()
