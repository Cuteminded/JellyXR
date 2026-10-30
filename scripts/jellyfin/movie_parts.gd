class_name MovieParts
extends RefCounted

static func is_multipart(item: Dictionary) -> bool:
	return item.get("Type", "") in ["Movie", "Video"] and int(item.get("PartCount", 0)) > 1

static func select(parts: Array, index: int, movie_id: String) -> Dictionary:
	var selected: Dictionary = parts[index].duplicate(true)
	selected["MoviePartItems"] = parts
	selected["MoviePartIndex"] = index
	selected["MovieParentId"] = movie_id
	return selected

static func next(item: Dictionary) -> Dictionary:
	var parts: Array = item.get("MoviePartItems", [])
	var index := int(item.get("MoviePartIndex", -1)) + 1
	if index <= 0 or index >= parts.size(): return {}
	return select(parts, index, str(item.MovieParentId))
