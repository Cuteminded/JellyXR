extends SceneTree

const SOURCE := "res://assets/cinema.glb"
const OUTPUT := "res://assets/theatre/cinema.res"
const MATERIAL_SOURCE := "res://assets/theatre/materials.tres"

var groups: Dictionary = {}
var finishes: Dictionary = {}

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	finishes = load(MATERIAL_SOURCE).get_meta("finishes")
	var source: Node3D = load(SOURCE).instantiate()
	root.add_child(source)
	collect(source)
	var scene := Node3D.new()
	scene.name = "CinemaInterior"
	for material: Material in groups:
		var mesh: ArrayMesh = groups[material].commit()
		var arrays := mesh.surface_get_arrays(0)
		var colors := PackedColorArray()
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			var brightness := 0.32 + 0.45 * maxf(normal.normalized().dot(Vector3.UP), 0.0)
			brightness += 0.18 * maxf(normal.normalized().dot(Vector3(0.3, 0.4, 0.85).normalized()), 0.0)
			colors.append(Color(brightness, brightness, brightness))
		arrays[Mesh.ARRAY_COLOR] = colors
		var baked_mesh := ArrayMesh.new()
		baked_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var key := String(material.resource_name).replace("/", "")
		var finish: StandardMaterial3D = finishes.get(key, material).duplicate()
		finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		finish.vertex_color_use_as_albedo = true
		baked_mesh.surface_set_material(0, finish)
		var instance := MeshInstance3D.new()
		instance.name = String(material.resource_name).replace("/", "")
		instance.mesh = baked_mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(instance)
		instance.owner = scene
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("Theatre build: ", error, "; material batches: ", groups.size())
	source.free()
	scene.free()
	quit(error)

func collect(node: Node) -> void:
	if node.name == "wall_screen": return
	if node is MeshInstance3D:
		var orientation := Basis(Vector3.UP, PI)
		var placement := Transform3D(orientation, -(orientation * TheatreEnvironment.VIEWER_POSITION))
		for surface in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(surface)
			if not groups.has(material):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[material] = builder
			groups[material].append_from(node.mesh, surface, placement * node.global_transform)
	for child in node.get_children():
		collect(child)
