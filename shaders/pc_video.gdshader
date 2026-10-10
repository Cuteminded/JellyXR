shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D video_texture : source_color, filter_linear;
uniform bool stereo = false;
uniform bool swap_eyes = false;

void fragment() {
	vec2 coordinate = UV;
	if (stereo) {
		int eye = int(VIEW_INDEX);
		if (swap_eyes) { eye = 1 - eye; }
		coordinate.x = coordinate.x * 0.5 + float(eye) * 0.5;
	}
	ALBEDO = texture(video_texture, coordinate).rgb;
}
