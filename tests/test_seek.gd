extends SceneTree

class FakeVideo extends AndroidVideo:
	var last_seek := -1
	var opened_at := -1
	func position_ms() -> int: return 30000
	func duration_ms() -> int: return 120000
	func seek(value: int) -> void: last_seek = value
	func open(_url: String, _authorization: String, start_ms: int) -> void: opened_at = start_ms
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
	session.source["TranscodingUrl"] = "/Videos/fixture/master.m3u8?MediaSourceId=fixture"
	await app._seek_to(95000)
	assert(video.last_seek == 95000, "HLS seeks the full movie timeline in the decoder")
	assert(session.opened_at == -1 and session.stopped_at == -1, "HLS seeking keeps the current stream open")
	session.position_ticks = 450000000
	await app._play_stream("https://fixture.invalid/master.m3u8", {}, 45000)
	assert(video.opened_at == 45000, "HLS resume passes the absolute movie position to the decoder")
	assert(app.transcode_offset == 0, "HLS progress does not add the resume position twice")
	app.decoder_ready = true
	video.paused = true
	await app._seek_to(10000)
	assert(video.last_seek == 10000 and video.paused, "HLS can seek backward while preserving pause")
	session.source.erase("TranscodingUrl")
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
