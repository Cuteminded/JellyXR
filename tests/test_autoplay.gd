extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array[String] = []
	var fail_episodes := false
	var hold_episodes := false
	signal release_episodes
	var catalog := [
		{"Id": "first", "Name": "First episode", "Type": "Episode", "SeriesId": "show", "ParentIndexNumber": 1, "IndexNumber": 1},
		{"Id": "second", "Name": "Second episode", "Type": "Episode", "SeriesId": "show", "ParentIndexNumber": 1, "IndexNumber": 2, "UserData": {"Played": true}},
		{"Id": "third", "Name": "Next season", "Type": "Episode", "SeriesId": "show", "ParentIndexNumber": 2, "IndexNumber": 1}
	]

	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		calls.append(path)
		if path.begins_with("/Shows/show/Episodes?"):
			if hold_episodes: await release_episodes
			await get_tree().process_frame
			if fail_episodes: return {"ok": false, "error": "Offline"}
			var id := path.split("StartItemId=")[1].split("&")[0]
			var items := []
			for index in range(catalog.size()):
				if catalog[index].Id == id:
					items = catalog.slice(index, index + 2)
					break
			return {"ok": true, "data": {"Items": items}}
		if path.begins_with("/Users/user/Items/first"):
			return {"ok": true, "data": catalog[0]}
		return {"ok": true, "data": {"Items": []}}

class FixtureVideo extends VideoBackend:
	func available() -> bool: return true
	func position_ms() -> int: return 119500
	func duration_ms() -> int: return 120000

class FixtureSession extends PlaybackSession:
	var opened: Array[Dictionary] = []
	var stopped_at := 0
	var hold_stop := false
	signal release_stop

	func report(event: String, _paused: bool = false) -> void:
		if event == "Stopped":
			stopped_at = position_ticks
			if hold_stop: await release_stop
			await get_tree().process_frame

	func open(selected: Dictionary, _transcode: bool = false) -> void:
		item = selected
		opened.append(selected)

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(6): await process_frame

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.video.queue_free()
	app.api.queue_free()
	app.session.queue_free()
	var api := FixtureApi.new()
	api.user_id = "user"
	api.token = "fixture"
	var video := FixtureVideo.new()
	var session := FixtureSession.new()
	app.add_child(api)
	app.add_child(video)
	app.add_child(session)
	app.api = api
	app.video = video
	app.session = session
	video.ended.connect(app._ended)

	var result := await api.next_episode(api.catalog[0])
	check(result.data.get("Id") == "second", "Autoplay follows series order even when the next episode is already watched")
	check("Limit=2" in api.calls.back() and "SeasonId" not in api.calls.back(), "The lookup covers season boundaries with a bounded response")
	result = await api.next_episode(api.catalog[1])
	check(result.data.get("Id") == "third", "The last episode of a season advances to the next season")
	result = await api.next_episode({"Id": "first", "Type": "Episode"})
	check(result.data.get("Id") == "second", "Missing series metadata is recovered from episode details")
	result = await api.next_episode(api.catalog[2])
	check(result.data.is_empty(), "The series finale has no next episode")
	result = await api.next_episode({"Id": "unknown", "SeriesId": "show"})
	check(result.data.is_empty(), "An unknown current episode cannot restart the series")

	session.item = api.catalog[0]
	app.playing = true
	video.ended.emit()
	await settle()
	check(session.stopped_at == 1200000000, "Natural completion reports the full duration")
	var indicator: PlayerLoading = app.world.player_loading
	check(indicator.label.text == "Next episode in 5 seconds", "Completion shows the five-second countdown")
	check(indicator.episode_title.text == "Second episode", "The countdown identifies the next episode")
	check(indicator.is_visible_in_tree() and app.screen.visible and not app.panel.visible and not app.player_overlay.visible, "The countdown uses the loading panel on the video screen")
	check(indicator.cancel_button.visible and not indicator.spinner.visible, "Countdown mode replaces the spinner with episode details and cancellation")
	app._update_timeline()
	check(indicator.is_visible_in_tree(), "Timeline updates cannot hide an active countdown")
	var call_count := api.calls.size()
	video.ended.emit()
	await settle()
	check(api.calls.size() == call_count, "Duplicate completion signals do not create another countdown")
	await create_timer(1.1).timeout
	check(indicator.label.text == "Next episode in 4 seconds", "The visible countdown updates each second")
	indicator.cancel_button.pressed.emit()
	await create_timer(1.1).timeout
	check(session.opened.is_empty() and not app.playing, "Cancel autoplay prevents the next episode from opening")
	check(not indicator.visible and not app.screen.visible and not app.autoplay_pending, "Cancellation removes the countdown from the screen")

	session.item = api.catalog[1]
	app.playing = true
	video.ended.emit()
	await settle()
	check(indicator.episode_title.text == "Next season" and indicator.label.text == "Next episode in 5 seconds", "Cross-season playback also shows the countdown")
	await create_timer(5.2).timeout
	check(session.opened.size() == 1 and session.opened[0].Id == "third", "The countdown opens the next episode exactly once")
	check(app.playing, "Autoplay enters playback after the countdown")
	check(not app.autoplay_pending and indicator.label.text == "Loading video..." and indicator.spinner.visible and not indicator.cancel_button.visible, "Starting the next episode restores the normal loading indicator")

	app.playing = true
	session.item = api.catalog[0]
	video.ended.emit()
	await settle()
	app._screen_settings()
	await create_timer(5.2).timeout
	check(session.opened.size() == 1 and not indicator.visible, "Navigation cancels the overlay countdown and prevents autoplay")

	api.hold_episodes = true
	session.item = api.catalog[0]
	app.playing = true
	video.ended.emit()
	await settle()
	app._screen_settings()
	api.release_episodes.emit()
	await settle()
	check(app.shell.heading.text == "Settings", "A delayed next-episode response cannot replace a page opened by the user")
	api.hold_episodes = false

	session.hold_stop = true
	app.playing = true
	video.ended.emit()
	await settle()
	app._screen_settings()
	call_count = api.calls.size()
	session.release_stop.emit()
	await settle()
	check(api.calls.size() == call_count, "Navigation during stop reporting cancels the next-episode lookup")
	session.hold_stop = false

	api.fail_episodes = true
	app.playing = true
	await app._ended()
	check("Could not load the next episode" in app.status.text, "Lookup failures show a readable error")
	api.fail_episodes = false
	session.item = api.catalog[2]
	app.playing = true
	await app._ended()
	check(app.shell.heading.text != "Up next" and not app.playing, "The series finale returns to the library without autoplay")
	session.item = {"Id": "movie", "Type": "Movie"}
	app.playing = true
	call_count = api.calls.filter(func(path: String): return path.begins_with("/Shows/")).size()
	await app._ended()
	check(api.calls.filter(func(path: String): return path.begins_with("/Shows/")).size() == call_count, "Movies do not request a next episode")

	app.queue_free()
	await process_frame
	print("Episode autoplay checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
