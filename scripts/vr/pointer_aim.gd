class_name PointerAim
extends RefCounted

var position := Vector2.ZERO
var initialized := false

func update(raw: Vector2, delta: float, pressing: bool) -> Vector2:
	if not initialized or position.distance_to(raw) > 90.0:
		position = raw
		initialized = true
	elif not pressing or position.distance_to(raw) > 32.0:
		position = position.lerp(raw, 1.0 - exp(-delta / 0.035))
	return position

func reset() -> void:
	initialized = false
