extends SceneTree

class FixtureApi extends JellyfinClient:
	var detail_calls: Array[String] = []
	var seasons_list := [{"Id": "season-one", "Name": "Season 1", "IndexNumber": 1}, {"Id": "season-two", "Name": "Season 2", "IndexNumber": 2}]

	func request(_path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true, "data": {"Items": [], "TotalRecordCount": 0}}

	func details(id: String) -> Dictionary:
		detail_calls.append(id)
		await get_tree().process_frame
		return {"ok": true, "data": {"Id": id, "Name": "Selected series" if id == "show" else "Selected movie", "Type": "Series" if id == "show" else "Movie"}}

	func seasons(_series_id: String) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true, "data": {"Items": seasons_list}}

	func episodes(_series_id: String, season_id: String, _offset: int = 0) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true, "data": {"Items": [{"Id": season_id + "-episode", "Name": "Selected episode", "IndexNumber": 1}], "TotalRecordCount": 1}}

class FixtureVideo extends VideoBackend:
	var stops := 0
	func available() -> bool: return true
	func stop() -> void: stops += 1
	func toggle_pause() -> void: paused = not paused

class FixtureSession extends PlaybackSession:
	var opens := 0
	func report(_event: String, _paused: bool = false) -> void: pass
	func open(selected: Dictionary, _transcode: bool = false) -> void:
		item = selected
		opens += 1

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(10): await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.api.queue_free()
	app.video.queue_free()
	app.session.queue_free()
	var api := FixtureApi.new()
	var video := FixtureVideo.new()
	var session := FixtureSession.new()
	app.add_child(api)
	app.add_child(video)
	app.add_child(session)
	app.api = api
	app.video = video
	app.session = session

	await app._details({"Id": "movie"})
	var movie_view: DetailsView = app.page.get_child(0)
	await app._start(movie_view.item)
	app._player_action("library")
	await settle()
	check(app.page.get_child(0) == movie_view, "The player's Library button returns to the selected movie details")
	check(api.detail_calls == ["movie"], "Returning preserves the existing details page without another lookup")
	check(not app.player_overlay.visible and app.playing, "Opening the details hides the controls and preserves playback")
	video.paused = true
	movie_view.play_button.pressed.emit()
	await settle()
	check(session.opens == 1 and video.stops == 0 and not video.paused, "Returning to the active movie resumes the current decoder without restarting")
	check(app.player_overlay.visible, "The movie's play button returns to the playback controls")

	await app._details({"Id": "show"})
	await settle()
	var series_view: DetailsView = app.page.get_child(0)
	series_view.series_browser.open_season(api.seasons_list[1])
	await settle()
	var card: EpisodeCard = series_view.series_browser.episode_list.get_child(0)
	card.play_button.pressed.emit()
	await settle()
	check(session.item.get("SeasonId") == "season-two", "Playback remembers which season the selected episode belongs to")
	app._player_action("library")
	await settle()
	check(app.page.get_child(0) == series_view and series_view.series_browser.episode_section.visible, "Returning to a series keeps its episode list open")
	check(series_view.series_browser.selected_season.Id == "season-two", "The selected season survives the trip to the player")
	var opens := session.opens
	card.play_button.pressed.emit()
	await settle()
	check(session.opens == opens, "Returning to the active episode does not restart its stream")

	app._screen_settings()
	app._player_action("library")
	await settle()
	var restored: DetailsView = app.page.get_child(0)
	check(restored.item.Id == "show" and restored.series_browser.selected_season.Id == "season-two", "Replacing the details page still allows a return to the active series and season")
	check(restored.series_browser.episode_list.get_child_count() == 1, "Restored series details load the remembered season's episodes")
	restored.series_browser.all_seasons_button.pressed.emit()
	await settle()
	check(restored.series_browser.season_grid.get_child_count() == 2, "All seasons remains available after restoring the remembered season")

	session.item = {"Id": "season-one-episode", "Type": "Episode", "SeriesId": "show", "SeasonId": "season-one", "ParentIndexNumber": 1}
	await app._return_to_title()
	await settle()
	check(restored.series_browser.selected_season.Id == "season-one", "Returning after playback changes seasons opens the current episode's season")
	restored.back_button.pressed.emit()
	check(app.page.get_child(0) is LibraryView, "Back to library still opens the library grid")
	await settle()

	app.playing = false
	app.queue_free()
	await process_frame
	print("Player return checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
