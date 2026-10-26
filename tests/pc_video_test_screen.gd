extends SubViewport

var backend := PcVideo.new()
var material := ShaderMaterial.new()

func _init(decoder: Node, dimensions := Vector2i(640, 360)) -> void:
	size = dimensions
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 1.0
	camera.current = true
	add_child(camera)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0 * dimensions.x / dimensions.y, 2.0)
	mesh.mesh = quad
	material.shader = load("res://shaders/pc_video.gdshader")
	mesh.material_override = material
	add_child(mesh)
	backend.material = material
	backend.bridge = decoder
	add_child(backend)
	decoder.texture_changed.connect(backend._set_texture)

func image() -> Image:
	return get_texture().get_image()
