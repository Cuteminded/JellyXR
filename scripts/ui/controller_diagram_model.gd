class_name ControllerDiagramModel
extends Resource

@export var texture: Texture2D
@export var canvas_size := Vector2(180, 350)
@export var mirror_right := true
@export_range(12.0, 64.0) var hotspot_diameter := 44.0
@export var button_positions: Dictionary = {}
@export var button_labels: Dictionary = {}

func button_position(action: String, right_hand: bool) -> Vector2:
	var point: Vector2 = button_positions.get(action, Vector2.ZERO)
	if right_hand and mirror_right: point.x = canvas_size.x - point.x
	return point
