class_name PlayerSkipPopup
extends MeshInstance3D

signal skip_requested

var viewport: SubViewport
var button: Button
var panel_size := Vector2.ZERO
var available := false

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport = SubViewport.new()
	viewport.size = Vector2i(300, 90)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 1
	material.albedo_texture = viewport.get_texture()
	VrOverlayMaterial.apply_depth(material)
	material_override = material
	button = Widgets.button("Skip intro", func(): skip_requested.emit(), viewport)
	button.theme = Widgets.theme()
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := Widgets.surface(Color("101624db"), 22, 16)
		if state in ["hover", "pressed"]:
			style.set_border_width_all(3)
			style.border_color = Color("6de3cf") if state == "hover" else Color("47bda9")
		button.add_theme_stylebox_override(state, style)
	var focus := Widgets.surface(Color.TRANSPARENT, 22, 16)
	focus.set_border_width_all(3)
	focus.border_color = Color("6de3cf")
	button.add_theme_stylebox_override("focus", focus)
	visibility_changed.connect(func():
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		if not is_visible_in_tree(): button.release_focus())
	hide()

func update_segment(segment: Dictionary) -> void:
	available = not segment.is_empty()
	if not available:
		hide()
		return
	button.text = str(segment.label)
	button.accessibility_name = button.text

func fit_screen(width: float, aspect: float, curvature: float, controls_height: float = 0.0) -> void:
	panel_size = Vector2(width * 0.20, width * 0.06)
	if mesh == null: mesh = QuadMesh.new()
	mesh.size = panel_size
	position.x = width * 0.47 - panel_size.x / 2.0
	position.y = -width / aspect / 2.0 + width * 0.02 + panel_size.y / 2.0
	if controls_height > 0.0: position.y += controls_height + width * 0.02
	position.z = (1.0 - cos(curvature / 2.0)) * width / curvature + 0.035 if curvature > 0.001 else 0.035
