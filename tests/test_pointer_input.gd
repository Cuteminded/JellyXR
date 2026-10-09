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
	print("VR pointer and click feedback checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)

func sample(value: float, inside: bool = true) -> void:
	pointer.sample_trigger(value)
	pointer.aim(point, inside)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
