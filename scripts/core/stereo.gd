class_name Stereo
extends RefCounted

enum Mode { MONO, HALF_SBS, FULL_SBS, TOP_BOTTOM }

static func detect(source: Dictionary) -> Mode:
	var format := str(source.get("Video3DFormat", "")).to_lower()
	if format in ["halfsbs", "halfsidebyside"]:
		return Mode.HALF_SBS
	if format in ["fullsbs", "fullsidebyside"]:
		return Mode.FULL_SBS
	if format in ["fulltopandbottom", "topandbottom", "topbottom"]:
		return Mode.TOP_BOTTOM
	var filename := str(source.get("Path", "")).get_file().to_lower()
	var pattern := RegEx.new()
	pattern.compile("(?i)(?:^|[ ._\\-])(h(?:alf)?[ ._\\-]?sbs|f(?:ull)?[ ._\\-]?sbs)(?:$|[ ._\\-])")
	var match_result := pattern.search(filename)
	if match_result:
		return Mode.HALF_SBS if match_result.get_string(1).begins_with("h") else Mode.FULL_SBS
	pattern.compile("(?i)(?:^|[ ._\\-])(?:tb|ou|top[ ._\\-]?bottom|over[ ._\\-]?under)(?:$|[ ._\\-])")
	if pattern.search(filename): return Mode.TOP_BOTTOM
	return Mode.MONO

static func aspect(width: int, height: int, mode: Mode) -> float:
	if width <= 0 or height <= 0:
		return 16.0 / 9.0
	var ratio := float(width) / height
	if mode == Mode.FULL_SBS: return ratio / 2.0
	if mode == Mode.TOP_BOTTOM: return ratio * 2.0
	return ratio

static func mesh(width: float, aspect_ratio: float, curve: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 64
	for segment in range(count):
		for corner in [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var u: float = (segment + corner.x) / count
			var x: float = (u - 0.5) * width
			var z := 0.0
			if curve > 0.001:
				var radius := width / curve
				x = sin((u - 0.5) * curve) * radius
				z = (1.0 - cos((u - 0.5) * curve)) * radius
			surface.set_uv(Vector2(u, corner.y))
			surface.add_vertex(Vector3(x, (0.5 - corner.y) * width / aspect_ratio, z))
	surface.generate_normals()
	return surface.commit()
