shader_type spatial;
render_mode unshaded, cull_disabled;

uniform samplerExternalOES video_texture : source_color, filter_linear;
uniform bool video_ready = false;
uniform bool stereo = false;
uniform bool top_bottom = false;
uniform bool swap_eyes = false;
uniform mat4 texture_transform = mat4(1.0);
uniform vec2 video_frame_size = vec2(0.0);

#include "video_minification.gdshaderinc"

vec3 sample_video(vec2 uv) {
	uv.y = 1.0 - uv.y;
	uv = (texture_transform * vec4(uv, 0.0, 1.0)).xy;
	return texture(video_texture, uv).rgb;
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
	vec2 radius = video_filter_radius(coordinate, video_frame_size);
	ALBEDO = vec3(0.0);
	if (video_ready) {
		bool has_frame_size = all(greaterThan(video_frame_size, vec2(0.0)));
		if (has_frame_size) {
			vec2 inset = 0.5 / video_frame_size;
			eye_min += inset;
			eye_max -= inset;
		}
		if (has_frame_size && any(greaterThan(radius, vec2(0.0)))) {
			vec2 diagonal = vec2(radius.x, -radius.y);
			ALBEDO = (sample_video(clamp(coordinate - radius, eye_min, eye_max))
				+ sample_video(clamp(coordinate + radius, eye_min, eye_max))
				+ sample_video(clamp(coordinate - diagonal, eye_min, eye_max))
				+ sample_video(clamp(coordinate + diagonal, eye_min, eye_max))) * 0.25;
		} else {
			ALBEDO = sample_video(clamp(coordinate, eye_min, eye_max));
		}
	}
}
