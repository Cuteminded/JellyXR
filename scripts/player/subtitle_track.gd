class_name SubtitleTrack
extends Node

signal changed
var cues: Array[Dictionary] = []
var index := -1
var delay_ms := 0
var message := "Subtitles off"
var request: HTTPRequest
var generation := 0

static func supported(stream: Dictionary) -> bool:
	return stream.get("IsTextSubtitleStream", false) or str(stream.get("Codec", "")).to_lower() in ["srt", "subrip", "vtt", "webvtt", "ass", "ssa", "mov_text", "ttml"]

func clear() -> void:
	generation += 1
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null
	cues.clear()
	index = -1
	message = "Subtitles off"
	changed.emit()

func select(api: JellyfinClient, item_id: String, source_id: String, selected: int) -> void:
	clear()
	index = selected
	if selected < 0: return
	var current := generation
	message = "Loading subtitles..."
	changed.emit()
	request = HTTPRequest.new()
	request.timeout = 120.0
	request.body_size_limit = 16 * 1024 * 1024
	add_child(request)
	var path := "/Videos/%s/%s/Subtitles/%d/Stream.vtt?CopyTimestamps=true&AddVttTimeMap=false" % [item_id.uri_encode(), source_id.uri_encode(), selected]
	var error := request.request(api.server + path, PackedStringArray(["Authorization: " + api.authorization()]))
	if error != OK:
		message = "Could not request subtitles. Select the track to retry."
		request.queue_free()
		request = null
		changed.emit()
		return
	var response: Array = await request.request_completed
	if current != generation: return
	request.queue_free()
	request = null
	if response[0] != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		message = "Could not load subtitles. Select the track to retry."
	else:
		cues = parse(response[3].get_string_from_utf8())
		message = "Subtitles ready" if not cues.is_empty() else "No readable subtitle cues were returned."
	changed.emit()

static func timestamp(value: String) -> int:
	var parts := value.replace(",", ".").split(":")
	if parts.size() not in [2, 3]: return -1
	var seconds := 0.0
	for part in parts:
		if not part.is_valid_float(): return -1
		seconds = seconds * 60.0 + float(part)
	return roundi(seconds * 1000.0)

static func parse(document: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tags := RegEx.new()
	tags.compile("<[^>]*>")
	for block in document.replace("\r", "").split("\n\n", false):
		var lines := block.strip_edges().split("\n")
		if lines[0].begins_with("NOTE") or lines[0] in ["STYLE", "REGION"]: continue
		for line_index in range(lines.size()):
			if not " --> " in lines[line_index]: continue
			var times := lines[line_index].split(" --> ")
			var start := timestamp(times[0].strip_edges())
			var end := timestamp(times[1].strip_edges().get_slice(" ", 0))
			if start < 0 or end <= start: break
			var text := tags.sub("\n".join(lines.slice(line_index + 1)), "", true)
			text = text.replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ").replace("&quot;", '"').replace("&amp;", "&")
			result.append({"start": start, "end": end, "text": text})
			break
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.start < b.start)
	var latest_end := 0
	for cue in result:
		latest_end = maxi(latest_end, cue.end)
		cue["latest_end"] = latest_end
	return result

func text_at(position_ms: int) -> String:
	var time := position_ms - delay_ms
	var low := 0
	var high := cues.size()
	while low < high:
		var middle := (low + high) / 2
		if int(cues[middle].start) <= time: low = middle + 1
		else: high = middle
	var active := PackedStringArray()
	var cursor := low - 1
	while cursor >= 0 and int(cues[cursor].latest_end) > time:
		if int(cues[cursor].end) > time: active.insert(0, cues[cursor].text)
		cursor -= 1
	return "\n".join(active)
