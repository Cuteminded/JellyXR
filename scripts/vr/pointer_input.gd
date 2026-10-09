class_name PointerInput
extends RefCounted

var viewport: SubViewport
var trigger_down := false
var just_pressed := false
var mouse_down := false
var previous := Vector2(-1, -1)
var hovering := false

func sample_trigger(value: float) -> void:
	var next := value > 0.15 if trigger_down else value >= 0.35
	just_pressed = next and not trigger_down
	trigger_down = next

func aim(point: Vector2, inside: bool) -> void:
	if not inside:
		cancel()
		return
	if not hovering:
		hovering = true
		viewport.notify_mouse_entered()
	_move(point)
	if just_pressed:
		if OS.is_debug_build() and OS.get_name() == "Android":
			var hovered := viewport.gui_get_hovered_control()
			print("Jellyframe input: press at ", point.round(), " target=", hovered.get_class() if hovered else "none")
		mouse_down = true
		_button(true)
	elif mouse_down and not trigger_down:
		mouse_down = false
		_button(false)

func scroll(point: Vector2, amount: float) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if amount > 0 else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = point
	wheel.global_position = point
	wheel.factor = absf(amount)
	viewport.push_input(wheel, true)
	var release := wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release, true)

func cancel() -> void:
	if previous != Vector2(-1, -1): _move(Vector2(-1, -1))
	if mouse_down:
		mouse_down = false
		_button(false)
	if hovering:
		hovering = false
		viewport.notify_mouse_exited()

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = point - previous
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_down else 0
	previous = point
	viewport.push_input(motion, true)

func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = previous
	event.global_position = previous
	viewport.push_input(event, true)
