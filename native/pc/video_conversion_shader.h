#pragma once

static const char *video_conversion_shader = R"glsl(
#version 450
layout(local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 0) uniform sampler2D y_plane;
layout(set = 0, binding = 1) uniform sampler2D u_plane;
layout(set = 0, binding = 2) uniform sampler2D v_plane;
layout(rgba8, set = 0, binding = 3) uniform writeonly image2D destination;
layout(push_constant, std430) uniform Parameters {
    ivec2 size;
    ivec2 source_size;
    vec2 coefficients;
    float full_range;
    float transfer;
    int rotation;
    int interleaved;
    float sample_scale;
    float code_max;
    float source_peak;
    float padding[3];
} parameters;

float hable(float value) {
    return ((value * (0.15 * value + 0.05) + 0.004) /
        (value * (0.15 * value + 0.5) + 0.06)) - (0.02 / 0.3);
}

vec3 hdr_to_sdr(vec3 rgb) {
    rgb = clamp(rgb, 0.0, 1.0);
    if (parameters.transfer == 1.0) {
        vec3 p = pow(rgb, vec3(1.0 / 78.84375));
        rgb = pow(max(p - 0.8359375, 0.0) / max(18.8515625 - 18.6875 * p, 0.000001), vec3(1.0 / 0.1593017578125)) * (10000.0 / 203.0);
    } else {
        rgb = mix(rgb * rgb / 3.0, (exp((rgb - 0.55991073) / 0.17883277) + 0.28466892) / 12.0, greaterThan(rgb, vec3(0.5)));
        float scene_luminance = dot(rgb, vec3(0.2627, 0.6780, 0.0593));
        rgb *= pow(max(scene_luminance, 0.0), 0.2) * (1000.0 / 203.0);
    }
    if (parameters.coefficients.x > 0.26) {
        rgb = mat3(1.6605, -0.1246, -0.0182, -0.5876, 1.1329, -0.1006, -0.0728, -0.0083, 1.1187) * rgb;
    }
    rgb = max(rgb, vec3(0.0));
    float signal = max(max(rgb.r, rgb.g), rgb.b);
    float mapped = hable(signal) / max(hable(parameters.source_peak), 0.000001);
    rgb *= mapped / max(signal, 0.000001);
    return mix(rgb * 12.92, 1.055 * pow(rgb, vec3(1.0 / 2.4)) - 0.055, greaterThan(rgb, vec3(0.0031308)));
}

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, parameters.size))) return;
    vec2 uv = (vec2(pixel) + 0.5) / vec2(parameters.size);
    if (parameters.rotation == 1) uv = vec2(uv.y, 1.0 - uv.x);
    else if (parameters.rotation == 2) uv = 1.0 - uv;
    else if (parameters.rotation == 3) uv = vec2(1.0 - uv.y, uv.x);
    ivec2 source = clamp(ivec2(uv * vec2(parameters.source_size)), ivec2(0), parameters.source_size - 1);
    float y = texelFetch(y_plane, source, 0).r * parameters.sample_scale;
    vec2 chroma = texelFetch(u_plane, source / 2, 0).rg;
    float u = chroma.r * parameters.sample_scale - 512.0;
    float v = (parameters.interleaved == 1 ? chroma.g : texelFetch(v_plane, source / 2, 0).r) * parameters.sample_scale - 512.0;
    if (parameters.full_range > 0.5) { y /= parameters.code_max; u /= parameters.code_max; v /= parameters.code_max; }
    else { y = (y - 64.0) / 876.0; u /= 896.0; v /= 896.0; }
    float kr = parameters.coefficients.x;
    float kb = parameters.coefficients.y;
    float kg = 1.0 - kr - kb;
    vec3 rgb = vec3(y + 2.0 * (1.0 - kr) * v,
        y - 2.0 * kb * (1.0 - kb) / kg * u - 2.0 * kr * (1.0 - kr) / kg * v,
        y + 2.0 * (1.0 - kb) * u);
    if (parameters.transfer > 0.0) rgb = hdr_to_sdr(rgb);
    imageStore(destination, pixel, vec4(clamp(rgb, 0.0, 1.0), 1.0));
}
)glsl";
