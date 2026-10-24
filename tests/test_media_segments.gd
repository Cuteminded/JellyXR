extends SceneTree

class FakeClient extends JellyfinClient:
	signal respond
	var paths: Array[String] = []
	var response := {"ok": true, "data": {"Items": [{"Type": "Intro", "StartTicks": 100000000, "EndTicks": 400000000}]}}
	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		paths.append(path)
		await respond
		return response

class FakeVideo extends AndroidVideo:
	var position := 10000
	var last_seek := -1
	func position_ms() -> int: return position
	func duration_ms() -> int: return 120000
	func seek(value: int) -> void: last_seek = value
	func stop() -> void: pass

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var segments := MediaSegments.new()
	segments.segments = MediaSegments.parse({"Items": [
		{"Type": "Outro", "StartTicks": 900000000, "EndTicks": 1200000000},
		{"Type": "Intro", "StartTicks": 100000000, "EndTicks": 400000000},
		{"Type": "Recap", "StartTicks": 0, "EndTicks": 100000000},
		{"Type": "Commercial", "StartTicks": 0, "EndTicks": 100000000},
		{"Type": "Intro", "StartTicks": -1, "EndTicks": 100},
		{"Type": "Intro", "StartTicks": 100, "EndTicks": 1},
		{"Type": "Intro", "StartTicks": "bad", "EndTicks": 100}, null
	]})
	assert(segments.segments.size() == 3)
	assert(segments.active(0, 120000).label == "Skip recap")
	assert(segments.active(10000, 120000).target_ms == 40000)
	assert(segments.active(40000, 120000).is_empty())
	assert(segments.active(90000, 120000).target_ms == 119000)
	assert(segments.active(119000, 120000).is_empty())
	assert(segments.active(10000, 0).is_empty())
	assert(MediaSegments.parse(null).is_empty())
	assert(MediaSegments.parse({"Items": null}).is_empty())
	var api := FakeClient.new()
	root.add_child(api)
	segments.load_item(api, "episode/id")
	assert(api.paths == ["/MediaSegments/episode%2Fid"])
	segments.clear()
	api.respond.emit()
	assert(segments.segments.is_empty(), "Stopped playback rejects late responses")
	segments.load_item(api, "episode")
	api.respond.emit()
	assert(segments.segments.size() == 1)
	api.response = {"ok": false, "status": 404}
	segments.load_item(api, "missing")
	api.respond.emit()
	assert(segments.segments.is_empty(), "Missing API clears old timestamps")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var video := FakeVideo.new()
	app.add_child(video)
	app.video = video
	app.media_segments.segments = MediaSegments.parse({"Items": [{"Type": "Intro", "StartTicks": 100000000, "EndTicks": 400000000}]})
	app.playing = true
	app.decoder_ready = true
	app._update_timeline()
	assert(app.world.player_skip_popup.available)
	app.screen.show()
	app.panel.hide()
	app.player_overlay.hide()
	app.world._process(0.0)
	var popup: PlayerSkipPopup = app.world.player_skip_popup
	assert(popup.is_visible_in_tree(), "Skip popup works with playback controls hidden")
	assert(popup.position.x > 0 and popup.position.y < 0, "Popup sits at the bottom-right")
	var bottom := popup.position.y
	app.player_overlay.show()
	app.world._process(0.0)
	assert(popup.position.y > bottom, "Popup moves above visible controls")
	var pointer := LaserPointer.new()
	app.add_child(pointer)
	pointer.global_position = popup.global_position + Vector3(0, 0, 1)
	assert(pointer.points_at(popup, popup.panel_size), "Controller ray can target the popup")
	pointer.global_position.x += 10
	assert(not pointer.points_at(popup, popup.panel_size), "Other controls remain reachable outside the popup")
	app.panel.show()
	app.world._process(0.0)
	assert(not popup.visible, "Library and settings hide the popup")
	app.panel.hide()
	app.world._process(0.0)
	app.world.player_skip_popup.button.pressed.emit()
	assert(video.last_seek == 40000, "The button seeks to the intro end")
	app.session.method = "Transcode"
	app.session.source = {"TranscodingUrl": "/master.m3u8"}
	app._skip_segment()
	assert(video.last_seek == 40000, "HLS uses the same absolute seek")
	app.transcode_offset = 400000000
	app._update_timeline()
	assert(not app.world.player_skip_popup.available, "Progressive transcode uses absolute position")
	app.transcode_offset = 0
	app.decoder_ready = false
	app._update_timeline()
	assert(not app.world.player_skip_popup.available, "Loading hides skip actions")
	app.playing = false
	await app._stop(false)
	assert(app.media_segments.segments.is_empty())
	app.queue_free()
	api.queue_free()
	await process_frame
	print("Media segment checks: PASS")
	quit()
