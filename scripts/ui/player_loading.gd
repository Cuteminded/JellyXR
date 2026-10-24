class_name PlayerLoading
extends MeshInstance3D

signal cancelled

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
var spinner: Spinner
var episode_title: Label
var label: Label
var cancel_button: Button
var panel_size := Vector2.ZERO

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport = SubViewport.new()
	viewport.size = Vector2i(440, 170)
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
	var panel := PanelContainer.new()
	panel.theme = Widgets.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("101624ed"), 22, 18))
	viewport.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	spinner = Spinner.new()
	spinner.custom_minimum_size = Vector2(64, 64)
	body.add_child(spinner)
	episode_title = Widgets.label("", body, 22)
	episode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	episode_title.clip_text = true
	label = Widgets.label("Loading video...", body, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_button = Widgets.button("Cancel autoplay", func(): cancelled.emit(), body)
	visibility_changed.connect(_update_viewport)
	show_loading()
	hide()

func show_loading() -> void:
	_show_waiting("Loading video...")

func show_buffering() -> void:
	_show_waiting("Buffering video...")

func _show_waiting(message: String) -> void:
	if visible and label.text == message and spinner.visible and not cancel_button.visible and not episode_title.visible: return
	_set_height(170)
	spinner.show()
	episode_title.hide()
	cancel_button.hide()
	label.text = message
	show()

func _update_viewport() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func show_countdown(episode_name: String, seconds: int) -> void:
	_set_height(200)
	spinner.hide()
	episode_title.text = episode_name
	episode_title.tooltip_text = episode_name
	episode_title.show()
	label.text = "Next episode in %d seconds" % seconds
	cancel_button.show()
	show()

func _set_height(height: int) -> void:
	viewport.size.y = height
	panel_size.y = panel_size.x * float(height) / 440.0
	if mesh is QuadMesh: mesh.size = panel_size

func fit_screen(width: float, curvature: float) -> void:
	var quad := QuadMesh.new()
	panel_size = Vector2(width * 0.28, width * 0.28 * viewport.size.y / 440.0)
	quad.size = panel_size
	mesh = quad
	position.z = (1.0 - cos(curvature / 2.0)) * width / curvature + 0.03 if curvature > 0.001 else 0.03
