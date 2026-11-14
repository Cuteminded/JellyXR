vec2 video_filter_radius(vec2 uv, vec2 frame_size) {
	vec2 footprint = abs(dFdx(uv)) + abs(dFdy(uv));
	return max(footprint - 1.0 / max(frame_size, vec2(1.0)), vec2(0.0)) * 0.25;
}
