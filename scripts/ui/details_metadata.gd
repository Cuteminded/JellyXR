class_name DetailsMetadata
extends RefCounted

static func title(item: Dictionary, fallback: String = "Untitled") -> String:
	var name := str(item.get("Name", fallback))
	if item.get("Type", "") != "Episode": return name
	var episode := "%02d" % int(item.IndexNumber) if item.get("IndexNumber") != null else "??"
	var season := "%02d" % int(item.ParentIndexNumber) if item.get("ParentIndexNumber") != null else "??"
	return "S%s E%s %s" % [season, episode, name]

static func duration(ticks: int) -> String:
	var minutes := int(ticks / 600000000.0)
	if minutes < 60: return "%d min" % minutes
	return "%dh %02dm" % [int(minutes / 60.0), minutes % 60]

static func year(item: Dictionary) -> String:
	return str(int(item.ProductionYear)) if item.get("ProductionYear") else ""

static func facts(item: Dictionary) -> Array[String]:
	var values: Array[String] = []
	if item.get("ProductionYear"): values.append(year(item))
	if item.get("RunTimeTicks"): values.append(duration(int(item.RunTimeTicks)))
	if item.get("OfficialRating"): values.append(str(item.OfficialRating))
	if item.get("CommunityRating"): values.append("Rating %.1f / 10" % float(item.CommunityRating))
	return values

static func streams(item: Dictionary) -> Dictionary:
	var result := {}
	var media: Array = item.get("MediaStreams", []) if item.get("MediaStreams") else []
	if media.is_empty():
		var sources: Array = item.get("MediaSources", []) if item.get("MediaSources") else []
		if not sources.is_empty() and sources[0].get("MediaStreams"):
			media = sources[0].MediaStreams
	for stream in media:
		var kind := str(stream.get("Type", ""))
		if kind not in ["Video", "Audio"] or result.has(kind): continue
		var parts: Array[String] = []
		if stream.get("DisplayTitle"):
			result[kind] = str(stream.DisplayTitle)
			continue
		if kind == "Video" and stream.get("Height"): parts.append("%dp" % int(stream.Height))
		if stream.get("Codec"): parts.append(str(stream.Codec).to_upper())
		if kind == "Video" and stream.get("VideoRange"): parts.append(str(stream.VideoRange))
		if kind == "Audio" and stream.get("Channels"): parts.append("%d channels" % int(stream.Channels))
		if stream.get("Language"): parts.append(str(stream.Language).to_upper())
		if not parts.is_empty(): result[kind] = " / ".join(parts)
	return result
