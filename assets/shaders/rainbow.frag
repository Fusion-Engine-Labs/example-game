#version 330 core

in vec3 v_normal;
in vec3 v_world_position;

uniform vec4 u_base_color;
uniform float u_metallic;
uniform float u_roughness;
uniform vec3 u_emissive;

out vec4 FragColor;

const float TAU = 6.28318530718;

vec3 spectral(float hue) {
    return 0.5 + 0.5 * cos(TAU * (hue + vec3(0.0, 0.333333, 0.666667)));
}

void main() {
    vec3 normal = normalize(v_normal);
    float around = atan(v_world_position.z, v_world_position.x) / TAU;
    float hue = fract(0.62 + around * 0.22 + v_world_position.y * 0.11);
    vec3 key_light = normalize(vec3(-0.35, 0.7, 0.6));
    float diffuse = 0.38 + 0.62 * max(dot(normal, key_light), 0.0);
    vec3 view = normalize(vec3(0.0, 0.0, 1.0));
    vec3 half_vector = normalize(key_light + view);
    float shininess = mix(8.0, 96.0, 1.0 - clamp(u_roughness, 0.0, 1.0));
    float specular = pow(max(dot(normal, half_vector), 0.0), shininess) * (0.08 + 0.32 * u_metallic);
    FragColor = vec4(spectral(hue) * u_base_color.rgb * diffuse + vec3(specular) + u_emissive, u_base_color.a);
}
