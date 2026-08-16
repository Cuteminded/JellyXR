extends SceneTree

class FakeVideo extends AndroidVideo:
	var last_seek := -1
	func position_ms() -> int: return 30000
	func duration_ms() -> int: return 120000
	func seek(value: int) -> void: last_seek = value
	func stop() -> void: pass

class FakeSession extends PlaybackSession:
	var opened_at := -1
	var stopped_at := -1
	func report(event: String, _paused: bool = false) -> void:
		if event == "Stopped": stopped_at = position_ticks
	func open(_selected: Dictionary, _transcode: bool = false) -> void:
		opened_at = position_ticks

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var video := FakeVideo.new()
	var session := FakeSession.new()
	app.add_child(video)
	app.add_child(session)
	app.video = video
	app.session = session
	session.source = {"RunTimeTicks": 72000000000}
	app.playing = true
	app.decoder_ready = true
	await app._seek_to(80000)
	assert(video.last_seek == 80000, "Direct play seeks the native decoder")
	session.method = "Transcode"
	app.transcode_offset = 6000000000
	video.paused = true
	await app._seek_to(90000)
	assert(session.stopped_at == 6300000000, "Stop reporting includes the transcode offset")
	assert(session.opened_at == 900000000, "Transcode seeking requests the absolute movie time, including before the old stream start")
	assert(app.seek_paused and app.seeking, "Paused state survives the stream restart")
	assert(app._duration_ms() == 7200000, "Total duration comes from the movie rather than a shortened stream")
	app.playing = false
	print("Playback seek checks: PASS")
	quit()
