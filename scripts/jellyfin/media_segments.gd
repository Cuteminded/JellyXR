class_name MediaSegments
extends RefCounted

const LABELS := {"Intro": "Skip intro", "Outro": "Skip credits", "Recap": "Skip recap", "Preview": "Skip preview"}

var segments: Array[Dictionary] = []
var generation := 0

func clear() -> void:
	generation += 1
	segments.clear()

func load_item(api: JellyfinClient, item_id: String) -> void:
	clear()
	var current := generation
	var result := await api.request("/MediaSegments/" + item_id.uri_encode())
	if current != generation or not result.get("ok", false): return
	segments = parse(result.get("data"))

static func parse(data: Variant) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	if not data is Dictionary or not data.get("Items") is Array: return parsed
	for item in data.Items:
		if not item is Dictionary or not LABELS.has(item.get("Type")): continue
		var start: Variant = item.get("StartTicks")
		var end: Variant = item.get("EndTicks")
		if not (start is int or start is float) or not (end is int or end is float): continue
		if not is_finite(float(start)) or not is_finite(float(end)): continue
		if start < 0 or end <= start or end >= 9223372036854775807: continue
		var start_ms := int(start / 10000)
		var end_ms := int(end / 10000)
		if end_ms <= start_ms: continue
		parsed.append({"start_ms": start_ms, "end_ms": end_ms, "label": LABELS[item.Type]})
	parsed.sort_custom(func(a: Dictionary, b: Dictionary): return a.start_ms < b.start_ms)
	return parsed

func active(position_ms: int, duration_ms: int) -> Dictionary:
	if duration_ms <= 0: return {}
	for segment in segments:
		var target := mini(int(segment.end_ms), maxi(0, duration_ms - 1000))
		if position_ms >= segment.start_ms and position_ms < target:
			return {"label": segment.label, "target_ms": target}
	return {}
