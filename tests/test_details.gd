extends SceneTree

class FixtureApi extends JellyfinClient:
	func seasons(_series_id: String) -> Dictionary:
		return {"ok": true, "data": {"Items": []}}

var failures := 0
var selected: Array = []
var back_count := 0

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(8): await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func movie() -> Dictionary:
	return {
		"Id": "movie", "Type": "Movie", "Name": "Michael",
		"ProductionYear": 2026, "RunTimeTicks": 77400000000,
		"OfficialRating": "NL-12", "CommunityRating": 8.7,
		"Genres": ["Music", "Drama"], "Taglines": ["Discover the making of a king."],
		"Overview": "A portrait of Michael Jackson's journey from the Jackson Five to a solo career, exploring his music, ambition and life behind the performances.",
		"MediaStreams": [{"Type": "Video", "Height": 1080, "Codec": "hevc", "VideoRange": "SDR"}, {"Type": "Audio", "DisplayTitle": "AAC / 5.1 / English"}],
		"Studios": [{"Name": "Lionsgate"}, {"Name": "GK Films"}],
		"People": [{"Name": "Antoine Fuqua", "Type": "Director"}, {"Name": "John Logan", "Type": "Writer"}],
		"UserData": {"PlaybackPositionTicks": 7200000000}
	}

func show_details(shell: UiShell, item: Dictionary) -> DetailsView:
	for child in shell.page.get_children():
		shell.page.remove_child(child)
		child.queue_free()
	var view := DetailsView.new()
	view.api = FixtureApi.new()
	view.add_child(view.api)
	view.item = item
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.play_requested.connect(func(chosen: Dictionary): selected.append(chosen))
	view.back_requested.connect(func(): back_count += 1)
	shell.page.add_child(view)
	return view

func run_checks() -> void:
	check(load("res://scripts/main.gd").can_instantiate(), "The main screen must compile with the new details view.")
	root.size = Vector2i(1536, 960)
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	shell.select("movies", "Movies")
	shell.set_libraries([{"Id": "movies", "Name": "Movies", "CollectionType": "movies"}, {"Id": "tv", "Name": "TV shows", "CollectionType": "tvshows"}])
	var item := movie()
	var view := show_details(shell, item)
	await settle()
	check(view.play_button.text == "Resume", "Saved playback must offer Resume.")
	view.play_button.pressed.emit()
	check(selected == [item], "Resume must pass the original item to playback.")
	view.back_button.pressed.emit()
	check(back_count == 1, "Back must return to the library.")
	check(DetailsMetadata.facts(item).has("2h 09m"), "Runtime must use readable hours and minutes.")
	check(DetailsMetadata.streams(item).Video == "1080p / HEVC / SDR", "Video metadata must describe the actual stream.")
	check(view.overview_label.max_lines_visible == -1, "The full synopsis must remain readable.")
	check(view.play_button.get_global_rect().end.y <= view.scroll.get_global_rect().end.y, "Playback must be visible without scrolling at the Quest panel size.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/details-preview.png")
	item.Name = "A very long movie title that should wrap clearly without hiding its final words"
	item.Overview = "A long synopsis must remain available while scrolling. ".repeat(30)
	view = show_details(shell, item)
	for width in [1280, 960]:
		root.size.x = width
		await settle()
		check(view.body.size.x <= view.scroll.size.x, "Details must fit the available width at %d pixels." % width)
		check(view.title_label.get_global_rect().end.x <= view.scroll.get_global_rect().end.x, "Long titles must not escape the details panel.")
	root.size.x = 1536
	view = show_details(shell, {"Id": "plain", "Name": "A movie without artwork", "Type": "Movie", "Overview": null, "UserData": null, "Genres": null, "People": null})
	await settle()
	check(view.play_button.text == "Play movie", "Unstarted movies must offer Play movie.")
	check(view.overview_label.text == "No description available.", "Missing metadata must have a readable fallback.")
	view = show_details(shell, {"Id": "series", "Name": "Example series", "Type": "Series"})
	await settle()
	check(view.play_button == null, "Series must select episodes instead of playing the series itself.")
	check(view.series_browser != null, "Series must show a season browser.")
	check(view.series_browser.season_grid.get_child(0).text == "No seasons available.", "An empty series must have a readable fallback.")
	print("Details checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
