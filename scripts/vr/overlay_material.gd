class_name VrOverlayMaterial
extends RefCounted

const DEPTH_SCALE := 0.01

static func apply_depth(material: BaseMaterial3D) -> void:
	# Menus and controllers share a depth range in front of the room.
	material.use_z_clip_scale = true
	material.z_clip_scale = DEPTH_SCALE
	material.no_depth_test = false
