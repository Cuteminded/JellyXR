shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D video_texture : source_color, filter_linear, hint_default_black;
uniform bool stereo = false;
uniform bool top_bottom = false;
uniform bool swap_eyes = false;

#include "pc_video_yuv.gdshaderinc"

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
	ALBEDO = direct_yuv ? sample_video_yuv(coordinate, eye_min, eye_max) : texture(video_texture, coordinate).rgb;
}
