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
		return {"ok": true, "data": {"Id": id, "Name": "Selected series" if id == "show" else "Selected movie", "Type": "Series" if id == "show" else "Movie", "UserData": {"PlaybackPositionTicks": 7200000000}}}

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
	api.token = "fixture"
	app.shell.set_signed_in(true)
	app.video = video
	app.session = session
	app.libraries_loaded = true
	app.shell.set_libraries([{"Id": "movies", "Name": "Movies", "CollectionType": "movies"}])
	var library_button: Button = app.shell.buttons["movies"]
	app._open_library("movies", "Movies")
	await settle()
	var browsing: LibraryView = app.page.get_child(0)
	browsing.field.text = "Selected movie"
	await browsing.refresh(browsing.field.text)
	var scroll_content := Control.new()
	scroll_content.custom_minimum_size.y = 2000
	browsing.content.add_child(scroll_content)
	await settle()
	browsing.scroll.scroll_vertical = 300
	var browsing_scroll := browsing.scroll.scroll_vertical
	check(browsing_scroll > 0, "The return fixture starts partway down a library")
	for attempt in range(2):
		app._screen_settings()
		check(app.shell.home.text == "Library", "Settings label the return button Library")
		check(app.shell.settings_navigation.visible and not app.shell.libraries.visible, "Settings categories replace the library list")
		check(app.shell.home.visible and not app.shell.settings_button.visible and not app.shell.logout.visible, "Library is the only regular navigation action shown in settings")
		check(app.shell.settings_navigation.get_child_count() == 1, "Reopening settings does not duplicate category buttons")
		app.shell.home.pressed.emit()
		await settle()
		check(app.page.get_child(0) == browsing and app.shell.libraries.visible, "Library returns to the same browsing page and restores the libraries")
		check(app.shell.selected_id == "movies" and app.shell.heading.text == "Movies", "Returning restores the selected library and heading")
		check(browsing.search == "Selected movie" and browsing.field.text == browsing.search and browsing.scroll.scroll_vertical == browsing_scroll, "Returning preserves the search and scroll position")
		check(app.shell.home.text == "Home", "Normal browsing restores the Home button")
		check(app.shell.buttons["movies"] == library_button, "Returning Home preserves the loaded library buttons")
		check(app.shell.settings_navigation.get_child_count() == 0 and app.shell.settings_button.visible and app.shell.logout.visible, "Leaving settings clears categories and restores normal navigation")

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
	movie_view.play_from_start_button.pressed.emit()
	await settle()
	check(session.opens == 2 and video.stops == 1, "Play from start restarts an already playing title")
	check(session.item.UserData.PlaybackPositionTicks == 0, "Restarted playback receives a zero start position")
	check(movie_view.item.UserData.PlaybackPositionTicks == 7200000000, "Restarting does not overwrite the details page's saved progress")
	await app._stop(false)
	movie_view.play_from_start_button.pressed.emit()
	await settle()
	check(session.opens == 3 and session.item.UserData.PlaybackPositionTicks == 0, "Play from start also starts stopped titles at zero")

	await app._details({"Id": "show"})
	await settle()
	var series_view: DetailsView = app.page.get_child(0)
	series_view.series_browser.open_season(api.seasons_list[1])
	await settle()
	var card: EpisodeCard = series_view.series_browser.episode_list.get_child(0)
	app._screen_settings()
	app.shell.home.pressed.emit()
	await settle()
	check(app.page.get_child(0) == series_view and series_view.series_browser.selected_season.Id == "season-two", "Library returns to the same series and selected season from settings")
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

	api.token = "fixture"
	app.libraries_loaded = true
	root.use_xr = true
	app.playing = true
	app.screen.show()
	app._show_playback()
	app.player_overlay.hide()
	var stops_before_library := video.stops
	var opens_before_library := session.opens
	var paused_before_library := video.paused
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.page.get_child(0) is LibraryView and app.panel.visible, "B opens the library while video controls are hidden")
	check(app.playing and app.screen.visible and not app.player_overlay.visible, "B preserves playback and hides the player controls")
	check(video.stops == stops_before_library and session.opens == opens_before_library and video.paused == paused_before_library, "B does not stop, restart, or pause the video")
	await app._play_stream("", {}, 0)
	check(app.panel.visible and not app.player_overlay.visible, "A stream becoming ready does not replace a library opened with B")
	app._video_prepared()
	check(app.panel.visible, "Video preparation does not hide a library opened with B")
	var controller_library: Node = app.page.get_child(0)
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(not app.panel.visible and not app.player_overlay.visible and app.playing, "Pressing B again closes the library and returns to the video")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) == controller_library, "B reopens the library without rebuilding the page")
	app.world._controller_button_pressed("ax_button", &"right_hand")
	check(app.player_overlay.visible and not app.panel.visible, "A still opens the playback controls")
	app.world._controller_button_pressed("menu_button", &"left_hand")
	check(app.player_overlay.visible and not app.panel.visible, "Left menu is reserved for the runtime and does not change the UI")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.page.get_child(0) is SettingsView and app.panel.visible, "Y opens settings while playback controls are hidden")
	check(not app.player_overlay.visible, "Opening settings hides playback controls")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(not app.panel.visible and not app.player_overlay.visible, "Y closes settings without showing playback controls, just like B")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.panel.visible and app.page.get_child(0) is SettingsView, "Y reopens settings during playback")
	check(app.playing and video.stops == stops_before_library and session.opens == opens_before_library and video.paused == paused_before_library, "Settings toggling leaves playback uninterrupted")
	app.world._controller_button_pressed("by_button", &"left_hand")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) == controller_library, "After Y opens and closes settings, B restores the previous library page")
	check(app.shell.libraries.visible and not app.shell.settings_navigation.visible, "B restores library navigation after hidden settings")
	check(app.playing and video.stops == stops_before_library and session.opens == opens_before_library and video.paused == paused_before_library, "Returning from settings with B leaves playback uninterrupted")
	app.panel.hide()
	app.playing = false
	app.screen.hide()
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) is LibraryView, "B also opens the library outside playback")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(not app.panel.visible, "B also closes the library outside playback")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.panel.visible and app.page.get_child(0) is SettingsView, "Y opens settings from a hidden library")
	var settings_view := app.page.get_child(0) as SettingsView
	settings_view._show_section(3)
	var settings_generation: int = app.page_generation
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(not app.panel.visible and not app.player_overlay.visible and app.page.get_child(0) == settings_view, "Y hides settings from any section, just like B")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.panel.visible and app.page.get_child(0) == settings_view and settings_view.sections[3].visible, "Y restores the same settings page and selected section")
	check(app.page_generation == settings_generation, "Toggling settings does not rebuild the page")
	app._screen_settings()
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) is LibraryView, "B returns to browsing when settings are visible")
	var returned_library: Node = app.page.get_child(0)
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(not app.panel.visible and app.page.get_child(0) == returned_library, "Pressing B again hides the restored library")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) == returned_library, "B reopens the restored library without rebuilding it")
	await app._details({"Id": "movie"})
	app.playing = true
	app.screen.show()
	var controller_details: Node = app.page.get_child(0)
	var details_generation: int = app.page_generation
	var detail_calls_before_toggle := api.detail_calls.size()
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(not app.panel.visible and app.page.get_child(0) == controller_details, "B hides title details instead of navigating Home")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and app.page.get_child(0) == controller_details, "B restores the same title details during playback")
	check(app.page_generation == details_generation and api.detail_calls.size() == detail_calls_before_toggle, "Toggling details does not rebuild or reload the page")
	check(app.playing and app.screen.visible and video.stops == stops_before_library and session.opens == opens_before_library, "Toggling details leaves the playing video untouched")
	app.playing = false
	app.autoplay_pending = true
	app.panel.hide()
	app.screen.show()
	app.world.player_loading.show_countdown("Next episode", 5)
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.panel.visible and not app.autoplay_pending and not app.screen.visible, "B cancels autoplay when opening the library")
	api.token = ""
	app._show_login()
	var login_generation: int = app.page_generation
	var login_page: Node = app.page.get_child(0)
	check(app.shell.settings_button.disabled, "Settings navigation is disabled before sign-in")
	app.world._controller_button_pressed("by_button", &"right_hand")
	check(app.page_generation == login_generation, "B cannot bypass sign-in")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.page_generation == login_generation and app.page.get_child(0) == login_page, "Y cannot open settings before sign-in")
	app.world._controller_button_pressed("by_button", &"left_hand")
	app._screen_settings()
	app.shell.screen_settings.emit()
	app._player_action("settings")
	check(app.page_generation == login_generation and app.page.get_child(0) == login_page and app.panel.visible, "Every settings entry point leaves sign-in visible without a session")
	api.token = "fixture"
	app.world._controller_button_pressed("by_button", &"left_hand")
	app._screen_settings()
	check(app.page_generation == login_generation, "A token awaiting session validation cannot open settings from sign-in")
	app._show_library()
	check(not app.shell.settings_button.disabled, "Settings navigation is enabled after sign-in")
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(app.panel.visible and app.page.get_child(0) is SettingsView, "Y opens settings again after sign-in")
	api.token = ""
	app.panel.hide()
	var settings_generation_after_logout: int = app.page_generation
	app.world._controller_button_pressed("by_button", &"left_hand")
	check(not app.panel.visible and app.page_generation == settings_generation_after_logout, "Y cannot reopen retained settings after a session is cleared")
	root.use_xr = false
	await settle()

	app.playing = false
	app.queue_free()
	await process_frame
	print("Player return checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
