extends SceneTree

class FeedbackProbe extends MenuFeedback:
	var clicks := 0
	func _play() -> void:
		clicks += 1

var activations := 0
var failures := 0
var pointer := PointerInput.new()
var point := Vector2(110, 70)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var feedback := FeedbackProbe.new()
	root.add_child(feedback)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(500, 300)
	root.add_child(viewport)
	pointer.viewport = viewport
	var button := Widgets.button("Open library", func(): activations += 1, viewport)
	button.position = Vector2(40, 40)
	button.size = Vector2(180, 60)
	await process_frame
	check(button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "Buttons respond to the initial press")
	check(feedback.player.stream.get_length() > 0, "Click sound contains audio samples")
	sample(0.0)
	check(pointer.hovering, "The viewport receives pointer entry")
	sample(0.65)
	check(activations == 1, "Initial trigger press activates immediately")
	for value in [0.58, 0.62, 0.35, 0.59]: sample(value)
	check(activations == 1, "Trigger jitter cannot cause repeated activation")
	point = Vector2(250, 70)
	sample(0.1)
	check(activations == 1, "Moving off the button during release does not lose or repeat the click")
	point = Vector2(110, 70)
	sample(0.7, false)
	sample(0.8)
	check(activations == 1, "Holding a trigger while entering the panel does not click")
	sample(0.0)
	sample(0.7)
	pointer.cancel()
	sample(0.8)
	check(activations == 2 and not pointer.mouse_down, "Hiding the menu cancels mouse capture without reactivating on return")
	sample(0.0)
	sample(0.7)
	pointer.cancel()
	var other := PointerInput.new()
	other.viewport = viewport
	other.sample_trigger(0.7)
	other.aim(point, true)
	other.sample_trigger(0.0)
	other.aim(point, true)
	check(activations == 4, "Controller handoff releases the previous pointer before the new click")
	other.cancel()
	button.disabled = true
	sample(0.0)
	sample(0.7)
	check(activations == 4 and feedback.clicks == 4, "Disabled buttons do not activate or play click feedback")
	pointer.cancel()
	check(not pointer.hovering, "Cancellation clears viewport hover")
	var aim := PointerAim.new()
	aim.update(Vector2(100, 70), 0.016, false)
	check(aim.update(Vector2(120, 70), 0.016, true) == Vector2(100, 70), "Trigger squeeze preserves the displayed target for small aim movement")
	check(aim.update(Vector2(500, 70), 0.016, true) == Vector2(500, 70), "Large intentional aim changes do not select the old target")
	aim.reset()
	check(aim.update(Vector2(20, 40), 0.016, false) == Vector2(20, 40), "Switching panels resets aim smoothing")
	await check_player_pointer()
	print("VR pointer and click feedback checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)

func check_player_pointer() -> void:
	var overlay := PlayerOverlay.new()
	root.add_child(overlay)
	overlay.position.z = -2.0
	overlay.show()
	await process_frame
	await process_frame
	var laser := LaserPointer.new()
	laser.panel = overlay
	laser.viewport = overlay.viewport
	root.add_child(laser)
	laser.set_process(false)
	for menu in ["audio", "subtitles", "screen_mode", "statistics"]:
		laser.set_target(overlay, overlay.viewport, overlay.panel_size)
		var button: Button = overlay.submenu_buttons[menu]
		var target := button.get_global_rect().get_center()
		laser.input.sample_trigger(0.0)
		laser._update_aim(target, true, 0.016)
		var destination := laser.dot.global_position
		laser.input.sample_trigger(1.0)
		laser._update_aim(target, true, 0.016)
		check(overlay.active_menu == menu, "The laser opens the %s menu" % menu)
		check(laser.dot.global_position.is_equal_approx(destination), "Opening %s preserves the laser's world position during the resize" % menu)
		await process_frame
		await process_frame
		laser.set_target(overlay, overlay.viewport, overlay.panel_size)
		target = button.get_global_rect().get_center()
		laser.input.sample_trigger(0.0)
		laser._update_aim(target, true, 0.016)
		check(laser.dot.global_position.is_equal_approx(destination), "The laser stays on the %s button after layout settles" % menu)
		var blank := Vector2(10, 10)
		laser._update_aim(blank, true, 0.016)
		check(not laser.beam.visible and not laser.dot.visible and not laser.input.hovering, "Transparent space beside %s hides the laser and clears hover" % menu)
		laser._update_aim(overlay.quick_access.get_global_rect().get_center(), true, 0.016)
		check(laser.beam.visible and laser.dot.visible, "The visible %s menu accepts the laser" % menu)
		laser.input.cancel()
		laser.aim.reset()
		laser._update_aim(target, true, 0.016)
		laser.input.sample_trigger(1.0)
		laser._update_aim(target, true, 0.016)
		check(overlay.active_menu.is_empty(), "The laser closes the %s menu" % menu)
		check(laser.dot.global_position.is_equal_approx(destination), "Closing %s preserves the laser's world position during the resize" % menu)
		await process_frame
		await process_frame
		laser.input.sample_trigger(0.0)
		laser.input.cancel()
	laser.queue_free()
	overlay.queue_free()
	await process_frame

func sample(value: float, inside: bool = true) -> void:
	pointer.sample_trigger(value)
	pointer.aim(point, inside)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
