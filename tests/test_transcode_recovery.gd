extends SceneTree

class FixtureApi extends JellyfinClient:
	var reports: Array[Dictionary] = []
	var progress_during_stop: Callable
	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
		reports.append({"path": path, "body": body.duplicate(true)})
		if path == "/Sessions/Playing/Stopped":
			progress_during_stop.call()
			await get_tree().process_frame
		return {"ok": true, "data": {"PlaySessionId": "recovered", "MediaSources": [{"Id": "source", "TranscodingUrl": "/video/master.m3u8"}]}}

class FixtureVideo extends VideoBackend:
	var position := 0
	var opened_at := -1
	func available() -> bool: return true
	func position_ms() -> int: return position
	func stop() -> void: position = 0
	func open(_url: String, _authorization: String, start_ms: int) -> void:
		opened_at = start_ms
		position = 0

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

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
	var api := FixtureApi.new()
	var video := FixtureVideo.new()
	app.add_child(api)
	app.add_child(video)
	api.server = "https://fixture.invalid"
	api.progress_during_stop = func(): app._process(10.0)
	app.api = api
	app.video = video
	app.session.api = api
	for sample in [[true, 123456, 300000000, 1234560000], [false, 0, 900000000, 900000000]]:
		api.reports.clear()
		app.session.item = {"Id": "movie", "UserData": {"PlaybackPositionTicks": 300000000}}
		app.session.source = {"Id": "source"}
		app.session.media_source_id = "source"
		app.session.session_id = "original"
		app.session.method = "DirectPlay"
		app.session.active_playback_mode = "auto"
		app.session.started = sample[0]
		app.session.fallback_attempted = false
		app.session.position_ticks = sample[2]
		app.transcode_offset = 0
		app.playing = true
		app.decoder_ready = sample[0]
		video.position = sample[1]
		await app._video_failed("Fixture decoder failure")
		var request: Dictionary = api.reports.back()
		check(request.path.ends_with("/PlaybackInfo") and request.body.StartTimeTicks == sample[3], "Fallback requests the current position, including when progress runs during the stopped report")
		check(video.opened_at == int(sample[3] / 10000), "The replacement HLS decoder resumes at the saved position")
		app._process(10.0)
		check(app.session.position_ticks == sample[3], "Loading the replacement stream does not overwrite its resume position")
		if sample[0]:
			check(api.reports[0].body.PositionTicks == sample[3], "The stopped report records the position before the decoder resets")
	app.playing = false
	app.queue_free()
	await process_frame
	print("Transcode recovery checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
