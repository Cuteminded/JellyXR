extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array = []
	var fail_seasons := false
	var fail_episodes := false
	var empty_seasons := false
	var empty_episodes := false
	var watched_states: Dictionary = {}
	var watched_calls: Array = []
	var fail_watched := false
	var hold_watched := false
	signal release_watched

	func set_watched(id: String, watched: bool) -> Dictionary:
		watched_calls.append([id, watched])
		if hold_watched: await release_watched
		await get_tree().process_frame
		if fail_watched: return {"ok": false, "error": "Offline"}
		watched_states[id] = watched
		if id == "agatha":
			for season in season_items: watched_states[season.Id] = watched
		return {"ok": true, "data": {"Played": watched}}
	var season_items := [{"Id": "one", "Name": "Season 1", "IndexNumber": 1}, {"Id": "two", "Name": "Season 2", "IndexNumber": 2}]

	func seasons(_series_id: String) -> Dictionary:
		await get_tree().process_frame
		if fail_seasons: return {"ok": false, "error": "Offline"}
		for season in season_items:
			season["UserData"] = {"Played": watched_states.get(season.Id, false)}
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
		if offset == 0 and not items.is_empty():
			items[0]["MediaSources"] = [{"Id": "first"}, {"Id": "second"}]
		if watched_states.has(season_id):
			for item in items:
				item.UserData = {"Played": watched_states[season_id], "PlaybackPositionTicks": 0}
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
	check(first.title_label.text == "S01 E01 Seekest Thou the Road", "Episode titles show padded season and episode numbers before the title.")
	check(first.play_button.text == "Resume episode", "Started episodes must offer Resume.")
	first.play_button.pressed.emit()
	check(selected.back().Id == "one0", "Playback must receive the selected episode, not the series or season.")
	var version_requests: Array = []
	view.version_requested.connect(func(item: Dictionary): version_requests.append(item))
	first.version_button.pressed.emit()
	check(version_requests.size() == 1 and version_requests[0].Id == "one0" and selected.size() == 1, "Episode version requests reach the details view without starting playback.")
	check(browser.episode_list.get_child(1).version_button == null, "Episodes without multiple versions have no version button.")
	check(browser.episode_list.get_child(1).play_button.text == "Play episode", "Unstarted episodes must offer Play.")
	await capture("res://dist/episodes-preview.png")
	for width in [1280, 960]:
		root.size.x = width
		await settle()
		check(first.size.x <= view.scroll.size.x, "Episode cards must fit the available panel width.")
		check(first.title_label.get_global_rect().end.x <= view.scroll.get_global_rect().end.x, "Episode text must remain inside the panel.")
		check(is_equal_approx(view.back_button.global_position.y, browser.all_seasons_button.global_position.y) and is_equal_approx(view.back_button.global_position.y, browser.watched_control.button.global_position.y), "All three season navigation buttons share one row.")
		check(browser.watched_control.get_global_rect().end.x <= view.get_global_rect().end.x, "The season watched action fits the right edge.")
	root.size.x = 1536
	check(browser.watched_control.button.text == "Mark as watched", "Partly watched seasons offer Mark as watched.")
	browser.watched_control.button.pressed.emit()
	await settle()
	check(api.watched_calls == [["one", true]], "The season action sends the season ID rather than an episode or series ID.")
	check(browser.watched_control.button.text == "Mark as unwatched", "Watched seasons offer Mark as unwatched.")
	for card in browser.episode_list.get_children():
		check(card.watched_badge.visible and card.play_button.text == "Play episode", "All episode pages refresh their badges and progress after a season change.")
	browser.watched_control.button.pressed.emit()
	await settle()
	for card in browser.episode_list.get_children():
		check(not card.watched_badge.visible, "Marking a season unwatched refreshes every episode.")
	api.fail_watched = true
	browser.watched_control.button.pressed.emit()
	await settle()
	check(browser.watched_control.status.visible and not browser.watched_control.button.disabled, "A failed season change shows an error and permits retry.")
	check(not browser.episode_list.get_child(0).watched_badge.visible, "Failed season changes preserve episode state.")
	api.fail_watched = false
	api.hold_watched = true
	browser.watched_control.button.pressed.emit()
	browser.open_season(api.season_items[1])
	await settle()
	api.release_watched.emit()
	await settle()
	check(browser.selected_season.Id == "two" and browser.episode_list.get_child(0).item.Id == "two0", "A late season update cannot replace another season's view.")
	api.hold_watched = false
	browser.open_season(api.season_items[0])
	browser.all_seasons_button.pressed.emit()
	browser.open_season(api.season_items[1])
	await settle()
	check(browser.episode_list.get_child(0).item.Id == "two0", "Changing season must ignore an older episode response.")
	check(browser.episode_list.get_child(0).title_label.text == "S02 E01 Seekest Thou the Road", "Episode titles use the selected season when the response lacks a season number.")
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
	api.empty_episodes = false
	check(browser.watched_control.item.Id == "agatha" and not browser.all_seasons_button.visible, "The overview offers a series action without All seasons.")
	browser.watched_control.button.pressed.emit()
	await settle()
	check(api.watched_calls.back() == ["agatha", true], "The overview submits the series ID for a whole-series update.")
	check(browser.watched_control.button.text == "Mark as unwatched", "A watched series offers Mark as unwatched.")
	for card in browser.season_grid.get_children():
		check(card.item.UserData.Played, "The series action refreshes every season.")
	await capture("res://dist/series-watched-preview.png")
	browser.open_season(api.season_items[1])
	await settle()
	for card in browser.episode_list.get_children():
		check(card.watched_badge.visible, "Episodes in another season reflect the whole-series update.")
	browser.all_seasons_button.pressed.emit()
	await settle()
	api.fail_watched = true
	browser.watched_control.button.pressed.emit()
	await settle()
	check(browser.watched_control.status.visible and browser.watched_control.button.text == "Mark as unwatched", "A failed series change preserves state and shows an error.")
	api.fail_watched = false
	browser.watched_control.button.pressed.emit()
	await settle()
	check(api.watched_calls.back() == ["agatha", false] and browser.watched_control.button.text == "Mark as watched", "A whole series can be marked unwatched.")
	for card in browser.season_grid.get_children():
		check(not card.item.UserData.Played, "All seasons refresh to unwatched.")
	api.hold_watched = true
	browser.watched_control.button.pressed.emit()
	browser.open_season(api.season_items[0])
	await settle()
	api.release_watched.emit()
	await settle()
	check(browser.selected_season.Id == "one" and browser.watched_control.item.Id == "one", "A late series response cannot replace the season action.")
	api.hold_watched = false
	browser.all_seasons_button.pressed.emit()
	await settle()
	api.empty_seasons = true
	browser.load_seasons()
	await settle()
	check(browser.season_grid.get_child(0).text == "No seasons available.", "Empty series must have a readable message.")
	print("Series checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
