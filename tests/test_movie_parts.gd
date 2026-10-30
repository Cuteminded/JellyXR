extends SceneTree

class FixtureApi extends JellyfinClient:
	var calls: Array[String] = []
	var fail_parts := false
	var hold_parts := false
	signal release_parts
	var movie := {"Id": "movie", "Type": "Video", "Name": "Multipart video", "PartCount": 3.0, "RunTimeTicks": 120000000}
	var extra := [
		{"Id": "part-two", "Type": "Video", "Name": "Part two", "RunTimeTicks": 120000000, "UserData": {"PlaybackPositionTicks": 50000000}},
		{"Id": "part-three", "Type": "Video", "Name": "Part three", "RunTimeTicks": 120000000}
	]

	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		calls.append(path)
		if "/AdditionalParts?" in path:
			if hold_parts: await release_parts
			await get_tree().process_frame
			if fail_parts: return {"ok": false, "error": "Offline"}
			return {"ok": true, "data": {"Items": extra}}
		await get_tree().process_frame
		return {"ok": true, "data": {"Items": [], "TotalRecordCount": 0}}

class FixtureVideo extends VideoBackend:
	func available() -> bool: return true
	func position_ms() -> int: return 11900
	func duration_ms() -> int: return 12000

class FixtureSession extends PlaybackSession:
	var opened: Array[Dictionary] = []
	var stopped: Array = []
	var hold_stop := false
	signal release_stop

	func report(event: String, _paused: bool = false) -> void:
		if event == "Stopped":
			stopped.append([item.Id, position_ticks])
			if hold_stop: await release_stop
			await get_tree().process_frame

	func open(selected: Dictionary, _transcode: bool = false, _continuing: bool = false) -> void:
		item = selected
		opened.append(selected)

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func settle() -> void:
	for frame in range(10): await process_frame

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
	app.shell.set_signed_in(true)
	video.ended.connect(app._ended)

	var result := await api.movie_parts(api.movie)
	check(result.data.Items.map(func(part: Dictionary): return part.Id) == ["movie", "part-two", "part-three"], "Movie parts preserve the server order with the main item first")
	check(api.calls.back() == "/Videos/movie/AdditionalParts?UserId=user", "Additional parts are scoped to the signed-in user")
	var alternate := api.movie.duplicate(true)
	alternate.SelectedMediaSourceId = "alternate version"
	await api.movie_parts(alternate)
	check(api.calls.back().begins_with("/Videos/alternate%20version/AdditionalParts?"), "Version selection requests that version's parts with an escaped ID")
	alternate.erase("SelectedMediaSourceId")
	alternate.MediaSources = [{"Id": "default-version"}, {"Id": "other-version"}]
	await api.movie_parts(alternate)
	check(api.calls.back().begins_with("/Videos/default-version/AdditionalParts?"), "Parts use the same default media source as playback")
	api.extra.append(api.extra[0])
	result = await api.movie_parts(api.movie)
	check(result.data.Items.size() == 3, "Duplicate parts cannot create repeated playback")
	api.extra.pop_back()

	var movie_library_item := api.movie.duplicate(true)
	movie_library_item.Type = "Movie"
	check(MovieParts.is_multipart(movie_library_item), "Movie libraries support multipart playback")
	check(not MovieParts.is_multipart({"Type": "Folder", "PartCount": 3}), "Folder items are not playable multipart videos")
	await app._start(movie_library_item)
	check(session.item.has("MoviePartItems"), "Movie library playback still prepares its multipart sequence")
	await app._stop(false)
	await app._start(api.movie)
	check(session.item.Id == "movie" and session.item.MoviePartIndex == 0, "Normal movie playback prepares its multipart sequence")
	video.ended.emit()
	await settle()
	check(session.item.Id == "part-two" and session.item.UserData.PlaybackPositionTicks == 0, "Natural completion immediately starts part two from the beginning")
	check(session.stopped.back() == ["movie", 120000000], "Completion reports the finished part's full duration")
	check(api.extra[0].UserData.PlaybackPositionTicks == 50000000, "Autoplay does not mutate the server metadata")
	video.ended.emit()
	await settle()
	check(session.item.Id == "part-three", "The second part advances to the third")
	var opens := session.opened.size()
	video.ended.emit()
	await settle()
	check(not app.playing and session.opened.size() == opens, "The final part stops without looping")

	app._clear_page()
	app.shell.heading.text = "Movie details"
	var view := DetailsView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.api = api
	view.item = api.movie
	var selected: Array = []
	view.play_requested.connect(func(part: Dictionary): selected.append(part))
	app.page.add_child(view)
	await settle()
	check(view.movie_parts_view != null and view.movie_parts_view.choices.get_child_count() == 3, "Movie details list all parts")
	for width in [1536, 960]:
		root.size = Vector2i(width, 960)
		await settle()
		check(view.movie_parts_view.size.x <= view.scroll.size.x, "Part controls fit the available details width")
		check(view.movie_parts_view.choices.get_child(1).focus_mode == Control.FOCUS_ALL, "Part controls support keyboard focus")
	root.size = Vector2i(1536, 960)
	await settle()
	if "--capture" in OS.get_cmdline_user_args():
		view.scroll.ensure_control_visible(view.movie_parts_view)
		await settle()
		await RenderingServer.frame_post_draw
		app.viewport.get_texture().get_image().save_png("res://dist/movie-parts-preview.png")
	view.movie_parts_view.choices.get_child(1).pressed.emit()
	check(selected.size() == 1 and selected[0].Id == "part-two" and selected[0].MovieParentId == "movie", "Direct part selection retains the parent movie and remaining sequence")
	await app._start(selected[0])
	check(session.item.UserData.PlaybackPositionTicks == 50000000, "Direct part selection preserves that part's resume position")
	app._return_to_title()
	check(view.is_inside_tree() and app.page.get_children().has(view), "Returning from an additional part reuses the main movie details")
	await app._stop(false)
	opens = session.opened.size()
	video.ended.emit()
	await settle()
	check(session.opened.size() == opens and not app.playing, "Manual Stop prevents continuation even if a late ended signal arrives")

	api.fail_parts = true
	view.movie_parts_view.load_parts()
	await settle()
	check(view.movie_parts_view.choices.get_child(1).text == "Retry", "Part lookup failures offer retry")
	api.fail_parts = false
	view.movie_parts_view.choices.get_child(1).pressed.emit()
	await settle()
	check(view.movie_parts_view.choices.get_child_count() == 3, "Retry restores the part controls")

	api.hold_parts = true
	app._start(api.movie)
	await settle()
	await app._stop(false)
	api.release_parts.emit()
	await settle()
	check(session.opened.size() == opens, "A cancelled part lookup cannot start playback later")
	api.hold_parts = false

	await app._start(MovieParts.select(result.data.Items, 0, "movie"))
	session.hold_stop = true
	video.ended.emit()
	await settle()
	app._screen_settings()
	opens = session.opened.size()
	session.release_stop.emit()
	await settle()
	check(session.opened.size() == opens, "Navigation during completion reporting cancels the next part")
	session.hold_stop = false
	api.fail_parts = true
	await app._start(api.movie)
	check(not app.playing and "Could not load movie parts" in app.status.text, "Playback preparation failures show an error without starting a partial sequence")
	app.queue_free()
	await process_frame
	print("Movie parts checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
