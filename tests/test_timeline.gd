extends SceneTree

var seeks: Array[int] = []

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 300)
	root.add_child(viewport)
	var timeline := PlaybackTimeline.new()
	timeline.size = Vector2(800, 120)
	timeline.position = Vector2(40, 40)
	viewport.add_child(timeline)
	timeline.seek_requested.connect(func(value: int): seeks.append(value))
	timeline.update_time(75000, 7200000)
	assert(seeks.is_empty(), "Playback updates must not seek")
	assert(timeline.elapsed_label.text == "1:15" and timeline.duration_label.text == "2:00:00")
	timeline.update_time(5000, 0)
	assert(not timeline.slider.editable and timeline.duration_label.text == "--:--")
	timeline.update_time(30000, 120000)
	timeline.update_buffer(60000, 120000, true)
	assert(timeline.buffered_bar.value == 60000 and seeks.is_empty())
	timeline.update_buffer(-1, 120000, true)
	assert(timeline.buffered_bar.value == 0)
	timeline.update_buffer(180000, 120000, true)
	assert(timeline.buffered_bar.value == 120000)
	timeline.update_buffer(60000, 120000, false)
	assert(timeline.buffered_bar.value == 0)
	await process_frame
	await process_frame
	var rect := timeline.slider.get_global_rect()
	var point := Vector2(rect.position.x + rect.size.x * 0.6, rect.get_center().y)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	timeline.update_time(31000, 120000)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release, true)
	assert(seeks.size() == 1, "One slider interaction must issue one seek, got %d" % seeks.size())
	assert(seeks[0] > 60000 and seeks[0] < 85000, "The controller chooses the intended time")
	assert(PlaybackTimeline.format_time(-10) == "0:00")
	print("Playback timeline checks: PASS")
	quit()
