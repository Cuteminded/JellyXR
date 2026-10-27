class_name PlaybackTimeline
extends VBoxContainer

signal seek_requested(milliseconds: int)
var slider: HSlider
var elapsed_label: Label
var duration_label: Label
var dragging := false
var buffered_bar: ProgressBar

func _ready() -> void:
	var times := HBoxContainer.new()
	add_child(times)
	elapsed_label = Widgets.label("0:00", times, 20)
	elapsed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_label = Widgets.label("--:--", times, 20)
	var track_area := Control.new()
	track_area.custom_minimum_size.y = 56
	add_child(track_area)
	buffered_bar = ProgressBar.new()
	buffered_bar.show_percentage = false
	buffered_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buffered_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	buffered_bar.offset_top = 23
	buffered_bar.offset_bottom = 33
	buffered_bar.add_theme_stylebox_override("background", Widgets.surface(Color("445268"), 5))
	buffered_bar.add_theme_stylebox_override("fill", Widgets.surface(Color("8998af"), 5))
	track_area.add_child(buffered_bar)
	slider = HSlider.new()
	slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slider.custom_minimum_size.y = 56
	slider.step = 1000
	slider.scrollable = false
	slider.editable = false
	slider.tooltip_text = "Seek to a time"
	var track := Widgets.surface(Color.TRANSPARENT, 5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("6de3cf")
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	track_area.add_child(slider)
	slider.drag_started.connect(func(): dragging = true)
	slider.value_changed.connect(func(value: float):
		elapsed_label.text = format_time(int(value))
		if not dragging: seek_requested.emit(int(value)))
	slider.drag_ended.connect(func(changed: bool):
		dragging = false
		if changed: seek_requested.emit(int(slider.value)))
	visibility_changed.connect(func():
		if not is_visible_in_tree(): dragging = false)

func update_time(position_ms: int, duration_ms: int, ready: bool = true) -> void:
	if dragging: return
	slider.editable = ready and duration_ms > 0
	slider.set_block_signals(true)
	slider.max_value = maxi(1, duration_ms)
	slider.value = clampi(position_ms, 0, duration_ms) if duration_ms > 0 else 0
	slider.set_block_signals(false)
	elapsed_label.text = format_time(maxi(0, position_ms))
	duration_label.text = format_time(duration_ms) if duration_ms > 0 else "--:--"

func update_buffer(buffered_ms: int, duration_ms: int, ready: bool) -> void:
	buffered_bar.max_value = maxi(1, duration_ms)
	buffered_bar.value = clampi(buffered_ms, 0, duration_ms) if ready and buffered_ms >= 0 and duration_ms > 0 else 0

static func format_time(milliseconds: int) -> String:
	var seconds := maxi(0, milliseconds / 1000)
	if seconds >= 3600: return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]
