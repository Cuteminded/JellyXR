uniform bool direct_yuv = false;
uniform sampler2D y_plane : filter_linear, repeat_disable;
uniform sampler2D u_plane : filter_linear, repeat_disable;
uniform sampler2D v_plane : filter_linear, repeat_disable;
uniform vec2 source_size = vec2(1.0);
uniform int video_rotation = 0;
uniform bool interleaved_chroma = false;
uniform bool chroma_in_alpha = false;
uniform vec2 color_coefficients = vec2(0.2126, 0.0722);
uniform float full_range = 0.0;
uniform float transfer = 0.0;
uniform float sample_scale = 1020.0;
uniform float code_max = 1020.0;
uniform float source_peak = 4.926108;

float hable(float value) {
    return ((value * (0.15 * value + 0.05) + 0.004) /
        (value * (0.15 * value + 0.5) + 0.06)) - (0.02 / 0.3);
}

vec3 hdr_to_sdr(vec3 rgb) {
    rgb = clamp(rgb, 0.0, 1.0);
    if (transfer == 1.0) {
        vec3 p = pow(rgb, vec3(1.0 / 78.84375));
        rgb = pow(max(p - 0.8359375, 0.0) / max(18.8515625 - 18.6875 * p, 0.000001), vec3(1.0 / 0.1593017578125)) * (10000.0 / 203.0);
    } else {
        rgb = mix(rgb * rgb / 3.0, (exp((rgb - 0.55991073) / 0.17883277) + 0.28466892) / 12.0, greaterThan(rgb, vec3(0.5)));
        float scene_luminance = dot(rgb, vec3(0.2627, 0.6780, 0.0593));
        rgb *= pow(max(scene_luminance, 0.0), 0.2) * (1000.0 / 203.0);
    }
    if (color_coefficients.x > 0.26) {
        rgb = mat3(vec3(1.6605, -0.1246, -0.0182), vec3(-0.5876, 1.1329, -0.1006), vec3(-0.0728, -0.0083, 1.1187)) * rgb;
    }
    rgb = max(rgb, vec3(0.0));
    float signal = max(max(rgb.r, rgb.g), rgb.b);
    float mapped = hable(signal) / max(hable(source_peak), 0.000001);
    rgb *= mapped / max(signal, 0.000001);
    return clamp(rgb, vec3(0.0), vec3(1.0));
}

vec2 rotate_video_uv(vec2 uv) {
    if (video_rotation == 1) uv = vec2(uv.y, 1.0 - uv.x);
    else if (video_rotation == 2) uv = 1.0 - uv;
    else if (video_rotation == 3) uv = vec2(1.0 - uv.y, uv.x);
    return uv;
}

vec3 sample_video_yuv(vec2 uv, vec2 eye_min, vec2 eye_max) {
    vec2 first = rotate_video_uv(eye_min) * source_size;
    vec2 last = rotate_video_uv(eye_max) * source_size;
    vec2 lower = min(first, last);
    vec2 upper = max(first, last);
    vec2 pixel = rotate_video_uv(uv) * source_size;
    vec2 y_uv = clamp(pixel, lower + 0.5, upper - 0.5) / vec2(textureSize(y_plane, 0));
    // Keep filtering inside the selected eye and outside decoder padding.
    vec2 chroma_uv = clamp(pixel * 0.5, ceil(lower * 0.5) + 0.5, ceil(upper * 0.5) - 0.5) / vec2(textureSize(u_plane, 0));
    float y = texture(y_plane, y_uv).r * sample_scale;
    vec4 chroma = texture(u_plane, chroma_uv);
    float u = chroma.r * sample_scale - 512.0;
    // Texture2DRD exposes R8G8 as luminance-alpha; R16G16 keeps red-green.
    float v_sample = interleaved_chroma ? (chroma_in_alpha ? chroma.a : chroma.g) : texture(v_plane, chroma_uv).r;
    float v = v_sample * sample_scale - 512.0;
    if (full_range > 0.5) { y /= code_max; u /= code_max; v /= code_max; }
    else { y = (y - 64.0) / 876.0; u /= 896.0; v /= 896.0; }
    float kr = color_coefficients.x;
    float kb = color_coefficients.y;
    float kg = 1.0 - kr - kb;
    vec3 rgb = vec3(y + 2.0 * (1.0 - kr) * v,
        y - 2.0 * kb * (1.0 - kb) / kg * u - 2.0 * kr * (1.0 - kr) / kg * v,
        y + 2.0 * (1.0 - kb) * u);
    if (transfer > 0.0) {
        rgb = hdr_to_sdr(rgb);
        if (OUTPUT_IS_SRGB) rgb = mix(rgb * 12.92, 1.055 * pow(rgb, vec3(1.0 / 2.4)) - 0.055, greaterThan(rgb, vec3(0.0031308)));
        return rgb;
    }
    rgb = clamp(rgb, vec3(0.0), vec3(1.0));
    // Spatial materials expect linear RGB on the Mobile and Forward+ renderers.
    if (!OUTPUT_IS_SRGB) rgb = mix(rgb / 12.92, pow((rgb + 0.055) / 1.055, vec3(2.4)), greaterThan(rgb, vec3(0.04045)));
    return rgb;
}
