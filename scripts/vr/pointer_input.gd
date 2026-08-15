class_name PointerInput
extends RefCounted

var viewport: SubViewport
var trigger_down := false
var just_pressed := false
var mouse_down := false
var previous := Vector2(-1, -1)

func sample_trigger(value: float) -> void:
	var next := value > 0.25 if trigger_down else value >= 0.55
	just_pressed = next and not trigger_down
	trigger_down = next

func aim(point: Vector2, inside: bool) -> void:
	if not inside:
		cancel()
		return
	_move(point)
	if just_pressed:
		mouse_down = true
		_button(true)
	elif mouse_down and not trigger_down:
		mouse_down = false
		_button(false)

func cancel() -> void:
	if previous != Vector2(-1, -1): _move(Vector2(-1, -1))
	if mouse_down:
		mouse_down = false
		_button(false)

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
	event.position = previous
	event.global_position = previous
	viewport.push_input(event, true)
