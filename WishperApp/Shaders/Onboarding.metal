#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Warm-to-cool cinematic radial gradient with wave distortion
// Origin: bottom center (50%, 101%), radiates outward
// Orange → Peach → Pink → Lavender → Blue

[[ stitchable ]] half4 gradientWave(
    float2 position,
    half4 currentColor,
    float2 size,
    float time
) {
    float2 uv = position / size;

    // Subtle wave distortion
    float wave1 = sin(uv.x * 3.0 + time * 0.4) * 0.015;
    float wave2 = cos(uv.y * 2.5 + time * 0.3) * 0.012;
    float wave3 = sin((uv.x + uv.y) * 4.0 + time * 0.6) * 0.008;
    uv += float2(wave1 + wave3, wave2);

    // Radial distance from bottom center (50%, 101%)
    float2 center = float2(0.5, 1.01);
    float2 scaled = (uv - center) / float2(0.8, 0.8); // 125% size = 1/0.8
    float dist = length(scaled);

    // Color stops matching the CSS gradient
    // 10.5% → deep orange
    // 16%   → warm orange
    // 17.5% → light orange
    // 25%   → peach
    // 40%   → pink/rose
    // 65%   → lavender
    // 100%  → sky blue

    half3 c0 = half3(0.96, 0.34, 0.008); // rgba(245,87,2)
    half3 c1 = half3(0.96, 0.47, 0.008); // rgba(245,120,2)
    half3 c2 = half3(0.96, 0.55, 0.008); // rgba(245,140,2)
    half3 c3 = half3(0.96, 0.67, 0.39);  // rgba(245,170,100)
    half3 c4 = half3(0.93, 0.68, 0.79);  // rgba(238,174,202)
    half3 c5 = half3(0.79, 0.70, 0.84);  // rgba(202,179,214)
    half3 c6 = half3(0.58, 0.79, 0.91);  // rgba(148,201,233)

    half3 col;
    if (dist < 0.105) {
        col = c0;
    } else if (dist < 0.16) {
        float t = (dist - 0.105) / (0.16 - 0.105);
        col = mix(c0, c1, half(t));
    } else if (dist < 0.175) {
        float t = (dist - 0.16) / (0.175 - 0.16);
        col = mix(c1, c2, half(t));
    } else if (dist < 0.25) {
        float t = (dist - 0.175) / (0.25 - 0.175);
        col = mix(c2, c3, half(t));
    } else if (dist < 0.40) {
        float t = (dist - 0.25) / (0.40 - 0.25);
        col = mix(c3, c4, half(t));
    } else if (dist < 0.65) {
        float t = (dist - 0.40) / (0.65 - 0.40);
        col = mix(c4, c5, half(t));
    } else {
        float t = min((dist - 0.65) / (1.0 - 0.65), 1.0);
        col = mix(c5, c6, half(t));
    }

    // Darken for readability (multiply with dark overlay)
    col = col * half(0.35);

    return half4(col, 1.0) * currentColor.a;
}
