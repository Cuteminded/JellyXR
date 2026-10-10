class_name ViewingWorld
extends Node3D

signal menu_requested
var settings: JellyframeSettings
var camera: Camera3D
var viewport: SubViewport
var panel: MeshInstance3D
var screen: MeshInstance3D
var material: ShaderMaterial
var theatre: TheatreEnvironment
var player_overlay: PlayerOverlay
var pointers: Array[LaserPointer] = []

func setup() -> void:
	var xr := XRServer.find_interface("OpenXR")
	var immersive := xr != null and xr.is_initialized()
	var origin := XROrigin3D.new()
	add_child(origin)
	if immersive:
		get_viewport().use_xr = true
		camera = XRCamera3D.new()
		origin.add_child(camera)
	else:
		camera = Camera3D.new()
		camera.position.y = 1.6
		origin.add_child(camera)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1536, 960)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = false
	add_child(viewport)
	panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.4, 2.75)
	panel.mesh = quad
	var ui_material := StandardMaterial3D.new()
	ui_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ui_material.albedo_texture = viewport.get_texture()
	ui_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ui_material.no_depth_test = true
	ui_material.render_priority = 100
	panel.material_override = ui_material
	add_child(panel)
	screen = MeshInstance3D.new()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/video.gdshader" if OS.get_name() == "Android" else "res://shaders/pc_video.gdshader")
	screen.material_override = material
	screen.visible = false
	add_child(screen)
	player_overlay = PlayerOverlay.new()
	screen.add_child(player_overlay)
	_build_theatre()
	if immersive:
		for hand in ["left_hand", "right_hand"]:
			var pointer := LaserPointer.new()
			pointer.tracker = hand
			pointer.pose = "aim"
			pointer.panel = panel
			pointer.viewport = viewport
			pointer.button_pressed.connect(func(action: String):
				if action in ["menu_button", "ax_button", "by_button"]: menu_requested.emit())
			origin.add_child(pointer)
			pointers.append(pointer)
	else:
		panel.hide()
		var overlay := CanvasLayer.new()
		add_child(overlay)
		var container := SubViewportContainer.new()
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		container.stretch = true
		overlay.add_child(container)
		viewport.reparent(container)

func _process(_delta: float) -> void:
	if not player_overlay: return
	for pointer in pointers:
		if player_overlay.is_visible_in_tree():
			pointer.set_target(player_overlay, player_overlay.viewport, player_overlay.panel_size)
		else:
			pointer.set_target(panel, viewport, Vector2(4.4, 2.75))

func _build_theatre() -> void:
	theatre = TheatreEnvironment.new()
	add_child(theatre)
	theatre.build()
	theatre.visible = settings.environment == "Theatre"


