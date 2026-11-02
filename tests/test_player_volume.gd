extends SceneTree

class VolumeBridge extends RefCounted:
	var level := 1.0
	var opened_levels: Array[float] = []
	func set_volume(value: float) -> void: level = value
	func open_video(_url: String, _authorization: String, _start_ms: int) -> String:
		opened_levels.append(level)
		return ""

class AvailablePcVideo extends PcVideo:
	func available() -> bool: return true

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
	for child in app.get_children():
		if child is MenuFeedback: child.queue_free()
	await process_frame
	var bridge := VolumeBridge.new()
	app.video.bridge = bridge
	var controls: PlayerVolumeControl = app.player_overlay.volume_control
	controls.slider.value = 37
	check(is_equal_approx(app.video.volume, 0.37) and is_equal_approx(bridge.level, 0.37), "The player slider changes the video backend's actual audio level")
	controls.mute_button.pressed.emit()
	check(app.video.muted and bridge.level == 0.0 and controls.mute_button.button_pressed, "Mute silences playback without changing the slider level")
	check(controls.slider.value == 37 and controls.mute_button.accessibility_name == "Unmute", "Muted controls retain the volume and expose the unmute action")
	controls.mute_button.pressed.emit()
	check(not app.video.muted and is_equal_approx(bridge.level, 0.37), "Unmute restores the chosen volume")
	controls.mute_button.pressed.emit()
	controls.slider.value = 60
	check(not app.video.muted and is_equal_approx(bridge.level, 0.6), "Moving the slider above zero unmutes playback")
	app.video.set_volume(2.0)
	check(app.video.volume == 1.0 and controls.slider.value == 100, "Volume cannot exceed 100 percent")
	app.video.set_volume(-1.0)
	check(app.video.volume == 0.0 and controls.slider.value == 0, "Volume cannot go below zero")
	for sample in [[0, "volume_off.svg"], [20, "volume_low.svg"], [50, "volume_medium.svg"], [100, "volume_up.svg"]]:
		app.video.set_volume(float(sample[0]) / 100.0)
		check(controls.mute_button.icon.resource_path.ends_with(sample[1]), "The mute button icon reflects the playback volume")
	app.video.toggle_mute()
	check(controls.mute_button.icon.resource_path.ends_with("volume_off.svg"), "Muting overrides the volume icon with the muted symbol")
	app.video.toggle_mute()
	app.player_overlay.show()
	app.player_overlay.submenu_buttons["volume"].pressed.emit()
	await process_frame
	await process_frame
	check(controls.visible and app.player_overlay.active_menu == "volume", "The speaker button opens a dedicated volume pop-out")
	check(controls.mute_button.get_global_rect().end.x < controls.slider.get_global_rect().position.x, "The separate mute button sits to the left of the slider")
	check(is_equal_approx(controls.slider.get_global_rect().get_center().y, controls.mute_button.get_global_rect().get_center().y), "The slider and mute button share the same vertical center")
	check(app.player_overlay.controls_row.get_global_rect().end.x <= app.player_overlay.viewport.size.x, "The volume controls fit beside the player buttons")
	var pointer := PointerInput.new()
	pointer.viewport = app.player_overlay.viewport
	var slider_rect := controls.slider.get_global_rect()
	var drag_start := slider_rect.get_center()
	pointer.sample_trigger(0.0)
	pointer.aim(drag_start, true)
	await process_frame
	pointer.sample_trigger(0.8)
	pointer.aim(drag_start, true)
	var beyond_right := Vector2(app.player_overlay.viewport.size.x + 100, drag_start.y)
	pointer.sample_trigger(0.8)
	pointer.aim(beyond_right, false)
	pointer.sample_trigger(0.0)
	pointer.aim(beyond_right, false)
	check(is_equal_approx(app.video.volume, 1.0) and not app.video.muted and is_equal_approx(bridge.level, 1.0), "Dragging quickly beyond the right edge clamps volume to 100 percent without muting")
	pointer.sample_trigger(0.0)
	pointer.aim(drag_start, true)
	await process_frame
	pointer.sample_trigger(0.8)
	pointer.aim(drag_start, true)
	var volume_before_cancel: float = app.video.volume
	pointer.cancel()
	check(is_equal_approx(app.video.volume, volume_before_cancel), "Cancelling a volume drag preserves the last level instead of moving the slider to zero")
	app.player_overlay.set_photo_mode(true)
	check(not controls.visible, "Photo viewing hides video audio controls")
	app.player_overlay.set_photo_mode(false)
	var video := AvailablePcVideo.new()
	root.add_child(video)
	video.bridge = bridge
	video.set_volume(0.42)
	video.toggle_mute()
	video.open("first", "", 0)
	video.open("second", "", 10000)
	check(bridge.opened_levels == [0.0, 0.0] and is_equal_approx(video.volume, 0.42), "Playback restarts begin muted and preserve the selected level")
	video.toggle_mute()
	check(is_equal_approx(bridge.level, 0.42), "Unmuting after a restart restores the selected level")
	video.queue_free()
	app.queue_free()
	await process_frame
	print("Player volume checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
