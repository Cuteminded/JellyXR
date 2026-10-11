class_name PlayerLoading
extends MeshInstance3D

class Spinner extends Control:
	var angle := 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree(): return
		angle = fmod(angle + delta * TAU * 0.7, TAU)
		queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		draw_arc(center, 25.0, 0.0, TAU, 48, Color("34435b"), 5.0, true)
		draw_arc(center, 25.0, angle, angle + TAU * 0.7, 40, Color("6de3cf"), 5.0, true)

var viewport: SubViewport

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport = SubViewport.new()
	viewport.size = Vector2i(440, 170)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	material_override = material
	var panel := PanelContainer.new()
	panel.theme = Widgets.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("101624ed"), 22, 18))
	viewport.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var spinner := Spinner.new()
	spinner.custom_minimum_size = Vector2(64, 64)
	body.add_child(spinner)
	var label := Widgets.label("Loading video...", body, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hide()

func fit_screen(width: float, curvature: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(width * 0.28, width * 0.28 * 170.0 / 440.0)
	mesh = quad
	position.z = (1.0 - cos(curvature / 2.0)) * width / curvature + 0.03 if curvature > 0.001 else 0.03
