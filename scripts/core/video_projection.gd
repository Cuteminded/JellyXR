class_name VideoProjection
extends RefCounted

enum Mode { SCREEN, EQUIRECTANGULAR, EQUIRECTANGULAR_180 }

static func detect(source: Dictionary) -> Mode:
	var filename := str(source.get("Path", "")).get_file()
	var pattern := RegEx.new()
	pattern.compile("(?i)(?:^|[ ._\\-])(?:vr[ ._\\-]?)?(180|360)(?:deg)?(?:$|[ ._\\-])")
	var marker := pattern.search(filename)
	if not marker: return Mode.SCREEN
	return Mode.EQUIRECTANGULAR_180 if marker.get_string(1) == "180" else Mode.EQUIRECTANGULAR

static func horizontal_angle(mode: Mode) -> float:
	return PI if mode == Mode.EQUIRECTANGULAR_180 else TAU

static func sphere(radius: float = 50.0, horizontal_angle: float = TAU) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 64 if horizontal_angle <= PI else 128
	var rows := 64
	for row in range(rows):
		for column in range(columns):
			for corner in [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var uv := Vector2((column + corner.x) / columns, (row + corner.y) / rows)
				var longitude := (uv.x - 0.5) * horizontal_angle
				var latitude := uv.y * PI
				var direction := Vector3(sin(longitude) * sin(latitude), cos(latitude), -cos(longitude) * sin(latitude))
				surface.set_uv(uv)
				surface.set_normal(-direction)
				surface.add_vertex(direction * radius)
	return surface.commit()
