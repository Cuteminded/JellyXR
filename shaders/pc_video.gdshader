shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D video_texture : source_color, filter_linear, hint_default_black;
uniform bool stereo = false;
uniform bool top_bottom = false;
uniform bool swap_eyes = false;

#include "pc_video_yuv.gdshaderinc"
#include "video_minification.gdshaderinc"

vec3 sample_video(vec2 uv, vec2 eye_min, vec2 eye_max) {
	if (direct_yuv) {
		return sample_video_yuv(uv, eye_min, eye_max);
	}
	return texture(video_texture, clamp(uv, eye_min, eye_max)).rgb;
}

void fragment() {
	vec2 coordinate = UV;
	vec2 eye_min = vec2(0.0);
	vec2 eye_max = vec2(1.0);
	if (stereo) {
		int eye = int(VIEW_INDEX);
		if (swap_eyes) { eye = 1 - eye; }
		if (top_bottom) {
			coordinate.y = coordinate.y * 0.5 + float(eye) * 0.5;
			eye_min.y = float(eye) * 0.5;
			eye_max.y = eye_min.y + 0.5;
		} else {
			coordinate.x = coordinate.x * 0.5 + float(eye) * 0.5;
			eye_min.x = float(eye) * 0.5;
			eye_max.x = eye_min.x + 0.5;
		}
	}
	vec2 frame_size = direct_yuv ? source_size : vec2(textureSize(video_texture, 0));
	if (direct_yuv && (video_rotation == 1 || video_rotation == 3)) {
		frame_size = frame_size.yx;
	}
	vec2 radius = video_filter_radius(coordinate, frame_size);
	if (!direct_yuv) {
		vec2 inset = 0.5 / max(frame_size, vec2(1.0));
		eye_min += inset;
		eye_max -= inset;
	}
	if (any(greaterThan(radius, vec2(0.0)))) {
		vec2 diagonal = vec2(radius.x, -radius.y);
		ALBEDO = (sample_video(coordinate - radius, eye_min, eye_max)
			+ sample_video(coordinate + radius, eye_min, eye_max)
			+ sample_video(coordinate - diagonal, eye_min, eye_max)
			+ sample_video(coordinate + diagonal, eye_min, eye_max)) * 0.25;
	} else {
		ALBEDO = sample_video(coordinate, eye_min, eye_max);
	}
}
