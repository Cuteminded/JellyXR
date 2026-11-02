class_name PlayerVolumeControl
extends HBoxContainer

signal volume_changed(level: float)
signal mute_requested
var slider: HSlider
var mute_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(190, 68)
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("202a3d"), 12, 12))
	add_child(panel)
	slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(112, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 100
	slider.step = 1
	slider.scrollable = false
	var track := Widgets.surface(Color("445268"), 5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("6de3cf")
	for state in ["grabber_area", "grabber_area_highlight"]: slider.add_theme_stylebox_override(state, fill)
	for state in ["grabber", "grabber_highlight"]: slider.add_theme_icon_override(state, preload("res://assets/icons/material/timeline_grabber.svg"))
	slider.value_changed.connect(func(value: float): volume_changed.emit(value / 100.0))
	panel.add_child(slider)
	mute_button = Widgets.button("", func(): mute_requested.emit(), self)
	move_child(mute_button, 0)
	mute_button.custom_minimum_size = Vector2(68, 68)
	mute_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mute_button.add_theme_constant_override("icon_max_width", 32)
	mute_button.toggle_mode = true
	PlayerQuickAccess.style_button(mute_button, false)
	update_volume(1.0, false)

func update_volume(level: float, muted: bool) -> void:
	slider.set_value_no_signal(level * 100.0)
	slider.accessibility_name = "Volume %d percent" % roundi(level * 100.0)
	mute_button.set_pressed_no_signal(muted)
	if muted or level <= 0.0:
		mute_button.icon = preload("res://assets/icons/material/volume_off.svg")
	elif level <= 0.33:
		mute_button.icon = preload("res://assets/icons/material/volume_low.svg")
	elif level <= 0.66:
		mute_button.icon = preload("res://assets/icons/material/volume_medium.svg")
	else:
		mute_button.icon = preload("res://assets/icons/material/volume_up.svg")
	mute_button.accessibility_name = "Unmute" if muted else "Mute"
