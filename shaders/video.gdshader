shader_type spatial;
render_mode unshaded, cull_disabled;

uniform samplerExternalOES video_texture : source_color, filter_linear;
uniform bool video_ready = false;
uniform bool stereo = false;
uniform bool top_bottom = false;
uniform bool swap_eyes = false;
uniform mat4 texture_transform = mat4(1.0);

void fragment() {
	vec2 coordinate = UV;
	if (stereo) {
		int eye = int(VIEW_INDEX);
		if (swap_eyes) { eye = 1 - eye; }
		if (top_bottom) {
			coordinate.y = coordinate.y * 0.5 + float(eye) * 0.5;
		} else {
			coordinate.x = coordinate.x * 0.5 + float(eye) * 0.5;
		}
	}
	coordinate.y = 1.0 - coordinate.y;
	coordinate = (texture_transform * vec4(coordinate, 0.0, 1.0)).xy;
	ALBEDO = video_ready ? texture(video_texture, coordinate).rgb : vec3(0.0);
}
