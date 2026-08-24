class_name LibraryHero
extends PanelContainer

signal chosen(item: Dictionary)
var item: Dictionary
var artwork: ArtworkLoader

func _ready() -> void:
	custom_minimum_size.y = 240
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_theme_stylebox_override("panel", Widgets.surface(Color("20324a"), 18))
	var poster := TextureRect.new()
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(poster)
	artwork.fetch(poster, item, true)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.035, 0.065, 0.11, 0.97), Color(0.035, 0.065, 0.11, 0.35)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 12)
	margin.add_child(text)
	var eyebrow := Widgets.label("FROM YOUR LIBRARY", text, 15)
	eyebrow.add_theme_color_override("font_color", Color("9fe8dc"))
	var title := Widgets.label(item.get("Name", "Untitled"), text, 38)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var description := Widgets.label(str(item.get("Overview") if item.get("Overview") else "No description available."), text, 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	text.add_child(row)
	Widgets.accent(Widgets.button("View details", func(): chosen.emit(item), row))
