class_name MediaCard
extends Button

signal chosen(item: Dictionary)
var item: Dictionary
var artwork: ArtworkLoader

func _ready() -> void:
	custom_minimum_size = Vector2(210, 332)
	tooltip_text = item.get("Name", "Untitled")
	pressed.connect(func(): chosen.emit(item))
	add_theme_stylebox_override("normal", Widgets.surface(Color("151e2e"), 14, 0))
	var body := VBoxContainer.new()
	body.position = Vector2(8, 8)
	body.size = Vector2(194, 312)
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(194, 254)
	image_frame.add_theme_stylebox_override("panel", Widgets.surface(Color("25334a"), 8))
	image_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(image_frame)
	var fallback := Label.new()
	fallback.text = "J"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override("font_size", 64)
	fallback.add_theme_color_override("font_color", Color("8095b3"))
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_frame.add_child(fallback)
	var poster := TextureRect.new()
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if item.get("Type", "") == "Photo":
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_frame.add_child(poster)
	artwork.fetch(poster, item)
	var title := Widgets.label(item.get("Name", "Untitled"), body, 20)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var user_data: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var detail := DetailsMetadata.year(item)
	if item.get("Type", "") == "Photo": detail = ""
	if user_data.get("Played", false):
		_watched_badge(image_frame)
		accessibility_name = tooltip_text + ", watched"
	if item.get("Type", "") == "Series": detail += "  /  Series"
	var subtitle := Widgets.label(detail.trim_prefix("  /  "), body, 16)
	subtitle.add_theme_color_override("font_color", Color("b0bbce"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var progress := float(user_data.get("PlayedPercentage", 0))
	if progress > 0 and progress < 100:
		var bar := ProgressBar.new()
		bar.value = progress
		bar.show_percentage = false
		bar.custom_minimum_size.y = 4
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", Widgets.surface(Color("29374b"), 2))
		bar.add_theme_stylebox_override("fill", Widgets.surface(Color("6de3cf"), 2))
		body.add_child(bar)

func _watched_badge(image_frame: PanelContainer) -> void:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_frame.add_child(overlay)
	var badge := TextureRect.new()
	badge.texture = preload("res://assets/icons/watched.svg")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -36
	badge.offset_top = 8
	badge.offset_right = -8
	badge.offset_bottom = 36
