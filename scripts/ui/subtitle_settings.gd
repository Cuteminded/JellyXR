class_name SubtitleSettings
extends VBoxContainer

signal appearance_changed
var settings: JellyXRSettings
var subtitles: SubtitleTrack
var timing_enabled := true
var color_buttons: Dictionary = {}

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	color_buttons.clear()
	add_theme_constant_override("separation", 12)
	_adjustment("Text size", func(): return str(settings.subtitle_size), func(step: int): settings.subtitle_size = clampi(settings.subtitle_size + step * 4, 28, 80))
	_adjustment("Vertical position", func(): return "%d%%" % roundi(settings.subtitle_height * 100), func(step: int): settings.subtitle_height = clampf(settings.subtitle_height + step * 0.05, 0.1, 0.8))
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 8)
	add_child(colors)
	var group := ButtonGroup.new()
	for color in ["White", "Yellow", "Green"]:
		var button := Widgets.button(color, func(): settings.subtitle_color = color; _save(), colors)
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.accessibility_name = color + " subtitles"
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = settings.subtitle_color == color
		PlayerQuickAccess.style_button(button)
		color_buttons[color] = button
	if subtitles == null:
		Widgets.label("Play a video to adjust subtitle timing.", self, 17)
		return
	_adjustment("Delay", func(): return "%+.1f s" % (subtitles.delay_ms / 1000.0), func(step: int): subtitles.delay_ms = clampi(subtitles.delay_ms + step * 100, -10000, 10000), false)
	var hint := Widgets.label("Positive delay shows subtitles later. Timing resets for each video.", self, 17)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("a4aec0"))
	var reset := Widgets.button("Reset timing", func(): subtitles.delay_ms = 0; refresh(), self)
	reset.custom_minimum_size = Vector2(0, 48)
	reset.disabled = not timing_enabled
	PlayerQuickAccess.style_button(reset)

func _adjustment(title: String, value: Callable, change: Callable, persist := true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var label := Widgets.label(title + ": " + value.call(), row, 19)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for step in [-1, 1]:
		var button := Widgets.button("-" if step < 0 else "+", func():
			change.call(step)
			label.text = title + ": " + value.call()
			if persist: _save(), row)
		button.disabled = not persist and not timing_enabled
		button.accessibility_name = ("Decrease " if step < 0 else "Increase ") + title.to_lower()
		button.custom_minimum_size = Vector2(48, 48)
		PlayerQuickAccess.style_button(button)

func _save() -> void:
	settings.save()
	appearance_changed.emit()
