class_name VideoProjection
extends RefCounted

enum Mode { SCREEN, EQUIRECTANGULAR }

static func detect(source: Dictionary) -> Mode:
	var filename := str(source.get("Path", "")).get_file()
	var pattern := RegEx.new()
	pattern.compile("(?i)(?:^|[ ._\\-])(?:vr[ ._\\-]?)?360(?:deg)?(?:$|[ ._\\-])")
	return Mode.EQUIRECTANGULAR if pattern.search(filename) else Mode.SCREEN

static func sphere(radius: float = 50.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 128
	var rows := 64
	for row in range(rows):
		for column in range(columns):
			for corner in [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var uv := Vector2((column + corner.x) / columns, (row + corner.y) / rows)
				var longitude := (uv.x - 0.5) * TAU
				var latitude := uv.y * PI
				var direction := Vector3(sin(longitude) * sin(latitude), cos(latitude), -cos(longitude) * sin(latitude))
				surface.set_uv(uv)
				surface.set_normal(-direction)
				surface.add_vertex(direction * radius)
	return surface.commit()
