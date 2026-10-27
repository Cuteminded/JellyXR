extends SceneTree

class FixtureApi extends JellyfinClient:
	var reports: Array[Dictionary] = []

	func request(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
		reports.append({"path": path, "method": method, "body": body.duplicate(true)})
		await get_tree().process_frame
		return {"ok": true, "data": {}}

class FixtureVideo extends VideoBackend:
	var position := 0

	func position_ms() -> int: return position
	func stop() -> void: position = 0

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
	app.api = api
	app.video = video
	app.session.api = api
	app.session.item = {"Id": "movie", "RunTimeTicks": 72000000000}
	app.session.source = {"Id": "source"}
	app.session.session_id = "session"
	for mode in ["DirectPlay", "HLS", "Transcode"]:
		api.reports.clear()
		app.session.method = "DirectPlay" if mode == "DirectPlay" else "Transcode"
		app.session.source["TranscodingSubProtocol"] = "hls" if mode == "HLS" else ""
		app.session.started = true
		app.session.position_ticks = 100000000
		app.transcode_offset = 6000000000 if mode == "Transcode" else 0
		video.position = 123456
		video.paused = mode == "HLS"
		var expected_ticks: int = app.transcode_offset + video.position * 10000
		app.playing = true
		app.decoder_ready = true
		app.player_overlay.stop_button.pressed.emit()
		for frame in range(6): await process_frame
		check(not app.playing and video.position == 0, "Stop closes the decoder")
		check(not app.session.started, "Stop closes the playback session")
		check(not api.reports.is_empty(), "Stop sends a Jellyfin request")
		if api.reports.is_empty(): continue
		var report: Dictionary = api.reports[0]
		check(report.path == "/Sessions/Playing/Stopped" and report.method == HTTPClient.METHOD_POST, "Stop posts to Jellyfin's stopped endpoint")
		check(report.body.PositionTicks == expected_ticks, "%s reports the current position before the decoder resets" % mode)
		check(report.body.ItemId == "movie" and report.body.MediaSourceId == "source" and report.body.PlaySessionId == "session", "Stop identifies the playing item and session")
		check(api.reports.size() == (1 if mode == "DirectPlay" else 2), "Stop reports once and cleans up transcoding when needed")
	app.queue_free()
	await process_frame
	print("Stop progress checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
