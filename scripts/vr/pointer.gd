class_name LaserPointer
extends XRController3D

var panel: Node3D
var viewport: SubViewport
var panel_size := Vector2(4.4, 2.75)
var beam: MeshInstance3D
var dot: MeshInstance3D
var input := PointerInput.new()
static var active_pointer: LaserPointer

func _ready() -> void:
	input.viewport = viewport
	if tracker == &"right_hand": active_pointer = self
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("6de3cf")
	beam = MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.002
	shape.bottom_radius = 0.002
	shape.height = 1.0
	beam.mesh = shape
	beam.rotation.x = PI / 2
	beam.material_override = material
	add_child(beam)
	dot = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.009
	sphere.height = 0.018
	dot.mesh = sphere
	dot.material_override = material
	add_child(dot)

func _process(delta: float) -> void:
	input.sample_trigger(get_float("trigger"))
	if input.just_pressed and get_is_active():
		if is_instance_valid(active_pointer) and active_pointer != self:
			active_pointer._cancel()
		active_pointer = self
	if (is_instance_valid(active_pointer) and active_pointer != self) or not get_is_active() or not panel.visible:
		_cancel()
		return
	var inverse := panel.global_transform.affine_inverse()
	var origin := inverse * global_position
	var direction := inverse.basis * -global_basis.z
	var distance := -origin.z / direction.z if absf(direction.z) > 0.00001 else -1.0
	var hit := origin + direction * distance
	var inside := distance > 0 and absf(hit.x) < panel_size.x / 2 and absf(hit.y) < panel_size.y / 2
	beam.visible = inside
	dot.visible = inside
	var point := Vector2(hit.x / panel_size.x + 0.5, 0.5 - hit.y / panel_size.y) * Vector2(viewport.size)
	input.aim(point, inside)
	if not inside: return
	beam.scale.y = distance
	beam.position.z = -distance / 2
	dot.position.z = -distance + 0.012
	if not input.trigger_down: _scroll(point, delta)

func _scroll(point: Vector2, delta: float) -> void:
	var scroll := get_vector2("primary").y
	if absf(scroll) <= 0.5: return
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if scroll > 0 else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = point
	wheel.factor = absf(scroll) * delta * 12.0
	viewport.push_input(wheel, true)

func _cancel() -> void:
	beam.hide()
	dot.hide()
	input.cancel()
