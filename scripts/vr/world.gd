class_name ViewingWorld
extends Node3D

signal menu_requested
var settings: JellyframeSettings
var camera: Camera3D
var viewport: SubViewport
var panel: MeshInstance3D
var screen: MeshInstance3D
var panorama: MeshInstance3D
var panoramic := false
var panorama_angle := TAU
var material: ShaderMaterial
var theatre: TheatreEnvironment
var passthrough := PassthroughEnvironment.new()
var player_overlay: PlayerOverlay
var player_loading: PlayerLoading
var pointers: Array[LaserPointer] = []
var controller_models: OpenXRRenderModelManager

func setup() -> void:
	var xr := XRServer.find_interface("OpenXR")
	var immersive := xr != null and xr.is_initialized()
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	add_child(world_environment)
	passthrough.setup(get_viewport(), world_environment.environment, xr)
	if settings.environment == "Passthrough" and not passthrough.is_supported():
		settings.environment = "Void"
	apply_environment()
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
	ui_material.render_priority = 100
	VrOverlayMaterial.apply_depth(ui_material)
	panel.material_override = ui_material
	add_child(panel)
	screen = MeshInstance3D.new()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/video.gdshader" if OS.get_name() == "Android" else "res://shaders/pc_video.gdshader")
	screen.material_override = material
	screen.visible = false
	add_child(screen)
	panorama = MeshInstance3D.new()
	panorama.material_override = material
	panorama.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panorama.hide()
	add_child(panorama)
	player_overlay = PlayerOverlay.new()
	screen.add_child(player_overlay)
	player_loading = PlayerLoading.new()
	screen.add_child(player_loading)
	_build_theatre()
	if immersive:
		controller_models = OpenXRRenderModelManager.new()
		controller_models.render_model_added.connect(_prepare_controller_model)
		origin.add_child(controller_models)
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
	var show_panorama := panoramic and screen.visible
	if panorama.visible != show_panorama:
		panorama.visible = show_panorama
		apply_environment()
	if show_panorama: panorama.global_position = camera.global_position
	var loading_menu_visible := player_loading.is_visible_in_tree() and player_loading.cancel_button.visible
	var menu_visible := panel.is_visible_in_tree() or player_overlay.is_visible_in_tree() or loading_menu_visible
	var controllers_visible := not screen.visible or menu_visible
	if controller_models != null:
		controller_models.visible = controllers_visible
	for pointer in pointers:
		pointer.visible = controllers_visible
		if player_loading.is_visible_in_tree() and player_loading.cancel_button.visible:
			pointer.set_target(player_loading, player_loading.viewport, player_loading.panel_size)
		elif player_overlay.is_visible_in_tree():
			pointer.set_target(player_overlay, player_overlay.viewport, player_overlay.panel_size)
		else:
			pointer.set_target(panel, viewport, Vector2(4.4, 2.75))

func _prepare_controller_model(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null: continue
			var unshaded := source.duplicate() as BaseMaterial3D
			unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			VrOverlayMaterial.apply_depth(unshaded)
			node.set_surface_override_material(surface, unshaded)
	for child in node.get_children():
		_prepare_controller_model(child)

func _build_theatre() -> void:
	theatre = TheatreEnvironment.new()
	add_child(theatre)
	theatre.build(settings.environment == "Theatre")
	theatre.visible = settings.is_theatre()

func apply_environment() -> void:
	var immersive_video := panoramic and screen != null and screen.visible
	passthrough.apply(settings.environment == "Passthrough" and not immersive_video)
	if theatre != null:
		if settings.is_theatre(): theatre.set_low_res(settings.environment == "Theatre")
		theatre.visible = settings.is_theatre() and not immersive_video

func set_panoramic(enabled: bool, horizontal_angle: float = TAU) -> void:
	panoramic = enabled
	if enabled and (panorama.mesh == null or not is_equal_approx(panorama_angle, horizontal_angle)):
		panorama.mesh = VideoProjection.sphere(50.0, horizontal_angle)
		panorama_angle = horizontal_angle
	panorama.visible = enabled and screen.visible
	if enabled:
		panorama.global_position = camera.global_position
		panorama.global_rotation = Vector3(0.0, camera.global_rotation.y, 0.0)
	apply_environment()

func _exit_tree() -> void:
	if passthrough.viewport != null: passthrough.apply(false)


