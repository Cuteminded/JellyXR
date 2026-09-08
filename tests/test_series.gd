extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail_seasons := false
	var fail_episodes := false
	var empty_seasons := false
	var empty_episodes := false
	var season_items := [{"Id": "one", "Name": "Season 1", "IndexNumber": 1}, {"Id": "two", "Name": "Season 2", "IndexNumber": 2}]

	func seasons(_series_id: String) -> Dictionary:
		await get_tree().process_frame
		if fail_seasons: return {"ok": false, "error": "Offline"}
		return {"ok": true, "data": {"Items": [] if empty_seasons else season_items}}

	func episodes(series_id: String, season_id: String, offset: int = 0) -> Dictionary:
		calls.append([series_id, season_id, offset])
		await get_tree().process_frame
		await get_tree().process_frame
		if fail_episodes: return {"ok": false, "error": "Offline"}
		var items := []
		if not empty_episodes:
			for index in range(offset, mini(offset + 2, 4)):
				items.append({"Id": season_id + str(index), "Name": ["Seekest Thou the Road", "Circle Sewn with Fate", "Through the trials", "The final chapter"][index], "IndexNumber": index + 1, "RunTimeTicks": 24000000000, "CommunityRating": 7.0, "Overview": "Agatha and her companions face another trial on the Witches' Road.", "UserData": {"PlaybackPositionTicks": 3000000000 if index == 0 else 0, "Played": index == 1}})
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": 0 if empty_episodes else 4}}

var failures := 0
var selected: Array = []

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(12): await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func capture(path: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run_checks() -> void:
	root.size = Vector2i(1536, 960)
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	shell.select("tv", "TV shows")
	shell.set_libraries([{"Id": "movies", "Name": "Movies", "CollectionType": "movies"}, {"Id": "tv", "Name": "TV shows", "CollectionType": "tvshows"}])
	var api := FixtureApi.new()
	root.add_child(api)
	var view := DetailsView.new()
	view.api = api
	view.item = {"Id": "agatha", "Name": "Agatha All Along", "Type": "Series", "ProductionYear": 2024, "OfficialRating": "NL-12", "CommunityRating": 7.2, "Genres": ["Action", "Adventure", "Comedy"], "Overview": "Agatha sets out on the Witches' Road with a new coven to reclaim her powers.", "Studios": [{"Name": "Disney+"}]}
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.play_requested.connect(func(item: Dictionary): selected.append(item))
	shell.page.add_child(view)
	await settle()
	var browser := view.series_browser
	check(browser.season_grid.get_child_count() == 2, "Series must show each season as a poster card.")
	view.scroll.ensure_control_visible(browser.season_section)
	await settle()
	await capture("res://dist/series-preview.png")
	browser.season_grid.get_child(0).pressed.emit()
	await settle()
	check(api.calls == [["agatha", "one", 0], ["agatha", "one", 2]], "All episode pages must stay in the chosen season.")
	check(browser.episode_list.get_child_count() == 4, "Every episode page must appear in the list.")
	var first: EpisodeCard = browser.episode_list.get_child(0)
	check(first.play_button.text == "Resume episode", "Started episodes must offer Resume.")
	first.play_button.pressed.emit()
	check(selected.back().Id == "one0", "Playback must receive the selected episode, not the series or season.")
	check(browser.episode_list.get_child(1).play_button.text == "Play episode", "Unstarted episodes must offer Play.")
	await capture("res://dist/episodes-preview.png")
	for width in [1280, 960]:
		root.size.x = width
		await settle()
		check(first.size.x <= view.scroll.size.x, "Episode cards must fit the available panel width.")
		check(first.title_label.get_global_rect().end.x <= view.scroll.get_global_rect().end.x, "Episode text must remain inside the panel.")
	root.size.x = 1536
	browser.open_season(api.season_items[0])
	browser.all_seasons_button.pressed.emit()
	browser.open_season(api.season_items[1])
	await settle()
	check(browser.episode_list.get_child(0).item.Id == "two0", "Changing season must ignore an older episode response.")
	api.fail_episodes = true
	browser.open_season(api.season_items[0])
	await settle()
	check(browser.episode_list.get_child(0).text == "Could not load episodes.", "Episode errors must be visible.")
	api.fail_episodes = false
	browser.episode_list.get_child(1).pressed.emit()
	await settle()
	check(browser.episode_list.get_child_count() == 4, "Retry must restore the selected season's episodes.")
	api.empty_episodes = true
	browser.open_season(api.season_items[1])
	await settle()
	check(browser.episode_list.get_child(0).text == "No episodes available in this season.", "Empty seasons must have a readable message.")
	browser.all_seasons_button.pressed.emit()
	api.fail_seasons = true
	browser.load_seasons()
	await settle()
	check(browser.season_grid.get_child(0).text == "Could not load seasons.", "Season errors must offer recovery.")
	api.fail_seasons = false
	browser.season_grid.get_child(1).pressed.emit()
	await settle()
	check(browser.season_grid.get_child_count() == 2, "Retry must restore season selection.")
	api.empty_seasons = true
	browser.load_seasons()
	await settle()
	check(browser.season_grid.get_child(0).text == "No seasons available.", "Empty series must have a readable message.")
	print("Series checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
