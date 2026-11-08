extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array[String] = []
	var fail_trailers := false
	var empty := false
	var hold := false
	signal release

	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		calls.append(path)
		if hold: await release
		await get_tree().process_frame
		if path.ends_with("LocalTrailers"):
			if fail_trailers: return {"ok": false, "error": "Offline"}
			return {"ok": true, "data": [] if empty else [{"Id": "trailer", "Name": "Official trailer", "Type": "Trailer"}]}
		if path.ends_with("SpecialFeatures"):
			return {"ok": true, "data": [] if empty else [
				{"Id": "making-of", "Name": "Making of the movie", "Type": "Video", "ExtraType": "BehindTheScenes", "Overview": "How the crew filmed the final scene.", "RunTimeTicks": 7200000000, "UserData": {"PlaybackPositionTicks": 600000000}, "MediaSources": [{"Id": "hd"}, {"Id": "uhd"}]},
				{"Id": "trailer", "Name": "Official trailer", "Type": "Trailer", "ExtraType": "Trailer"}
			]}
		return {"ok": true, "data": {"Items": [], "TotalRecordCount": 0}}

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func settle() -> void:
	for frame in range(16): await process_frame

func run_checks() -> void:
	root.size = Vector2i(1536, 960)
	var api := FixtureApi.new()
	api.user_id = "user/name"
	root.add_child(api)
	var result := await api.extras("movie/id")
	check(api.calls == ["/Users/user%2Fname/Items/movie%2Fid/SpecialFeatures", "/Users/user%2Fname/Items/movie%2Fid/LocalTrailers"], "Extras use both user-scoped endpoints and encode identifiers")
	check(result.ok and result.data.Items.size() == 2, "Special features and trailers are combined without duplicate IDs")
	api.fail_trailers = true
	result = await api.extras("movie")
	check(not result.ok and result.data.Items.size() == 2, "A failed endpoint preserves extras from the successful endpoint")
	api.fail_trailers = false
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	var view := DetailsView.new()
	view.api = api
	view.item = {"Id": "movie", "Type": "Movie", "Name": "Example movie"}
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var selected: Array = []
	var versions: Array = []
	view.play_requested.connect(func(item: Dictionary): selected.append(item))
	view.version_requested.connect(func(item: Dictionary): versions.append(item))
	shell.page.add_child(view)
	await settle()
	var extras: VBoxContainer = view.extras_view
	check(extras.visible and extras.choices.get_child_count() == 2, "Movie details show playable extras")
	var card: EpisodeCard = extras.choices.get_child(0)
	check(card.play_button.text == "Resume extra" and card.facts_label.text.contains("Behind the scenes"), "Extras show their category and resume action")
	check(card.thumbnail.texture == null and card.title_label.text == "Making of the movie", "Extras without artwork retain readable titles")
	card.play_button.pressed.emit()
	card.version_button.pressed.emit()
	check(selected.size() == 1 and selected[0].Id == "making-of" and selected[0].ExtraReturnItem.Id == "movie", "Playing an extra preserves its parent and saved progress")
	check(versions.size() == 1 and versions[0].ExtraReturnItem.Id == "movie", "Choosing an extra version preserves its return destination")
	check(card.play_button.accessibility_name.contains("Making of the movie"), "Extra playback has a descriptive accessible name")
	for width in [1536, 960]:
		root.size.x = width
		await settle()
		view.scroll.scroll_vertical = int(extras.position.y)
		await settle()
		check(view.body.size.x <= view.scroll.size.x, "Extras fit the details width at %d pixels" % width)
		check(card.play_button.get_global_rect().end.x <= view.scroll.get_global_rect().end.x, "Extra playback stays within the available width")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://dist/extras-%d-preview.png" % width)
	api.fail_trailers = true
	await extras.load_extras()
	check(extras.choices.get_child_count() == 4 and extras.choices.get_child(3).text == "Retry extras", "Partial failures keep playable cards and offer retry")
	api.fail_trailers = false
	extras.choices.get_child(3).pressed.emit()
	await settle()
	check(extras.choices.get_child_count() == 2, "Retry replaces the failure state without duplicating extras")
	api.empty = true
	await extras.load_extras()
	check(not extras.visible, "Empty extras sections are hidden")
	api.empty = false
	var browser := SeriesBrowser.new()
	browser.api = api
	browser.artwork = view.artwork
	browser.series_id = "show"
	browser.series_item = {"Id": "show", "Type": "Series"}
	shell.page.add_child(browser)
	await settle()
	browser.open_season({"Id": "season-one", "Name": "Season 1"})
	await settle()
	check(browser.extras_view.item_id == "season-one", "Opening a season requests that season's extras")
	card = browser.extras_view.choices.get_child(0)
	check(card.item.ExtraReturnItem.Id == "show" and card.item.ExtraReturnSeason.Id == "season-one", "Season extras preserve series and season context")
	api.hold = true
	browser.open_season({"Id": "old-season", "Name": "Old season"})
	browser.open_season({"Id": "new-season", "Name": "New season"})
	api.hold = false
	api.release.emit()
	await settle()
	check(browser.extras_view.item_id == "new-season" and browser.extras_view.choices.get_child_count() == 2, "A late extras response cannot replace the newly selected season")
	browser._show_seasons()
	check(not browser.episode_section.visible, "Returning to all seasons hides season extras with the episode section")
	shell.queue_free()
	api.queue_free()
	await settle()
	print("Extras checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
