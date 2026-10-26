extends HSlider

var pending_steps := 0.0

func _init() -> void:
	scrollable = false
	tooltip_text = "Point here and move the joystick left or right to adjust."
	var track := Widgets.surface(Color("445268"), 7)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("6de3cf")
	add_theme_stylebox_override("grabber_area", fill)
	add_theme_stylebox_override("grabber_area_highlight", fill)
	_style_grabbers()
	mouse_exited.connect(func(): pending_steps = 0.0)

func _style_grabbers() -> void:
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var color := Color("8793a8") if state == "grabber_disabled" else Color("6de3cf")
		if state == "grabber_highlight": color = Color.WHITE
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([color, color, Color(color, 0)])
		gradient.offsets = PackedFloat32Array([0.0, 0.85, 1.0])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 26
		texture.height = 26
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		add_theme_icon_override(state, texture)

func adjust_horizontal(amount: float) -> void:
	if not editable: return
	if signf(amount) != signf(pending_steps): pending_steps = 0.0
	pending_steps += amount
	var steps := int(pending_steps)
	if steps == 0: return
	pending_steps -= steps
	value += steps * step
