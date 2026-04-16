#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Animated gradient wave background

[[ stitchable ]] half4 gradientWave(
    float2 position,
    half4 currentColor,
    float2 size,
    float time
) {
    // Normalize coordinates
    float2 uv = position / size;

    // Animated wave distortion
    float wave1 = sin(uv.x * 4.0 + time * 0.8) * 0.05;
    float wave2 = sin(uv.y * 3.0 + time * 0.6) * 0.04;
    float wave3 = cos((uv.x + uv.y) * 5.0 + time * 1.2) * 0.03;

    float distort = wave1 + wave2 + wave3;

    // Purple-to-blue gradient with wave distortion
    float t = uv.y + distort;
    half3 color1 = half3(0.35, 0.12, 0.65); // Deep purple
    half3 color2 = half3(0.15, 0.25, 0.75); // Blue
    half3 color3 = half3(0.55, 0.20, 0.70); // Vibrant purple

    half3 col;
    if (t < 0.5) {
        col = mix(color1, color2, half(t * 2.0));
    } else {
        col = mix(color2, color3, half((t - 0.5) * 2.0));
    }

    // Subtle radial glow from center
    float2 center = float2(0.5, 0.4);
    float dist = length(uv - center);
    float glow = 1.0 - smoothstep(0.0, 0.8, dist);
    col += half3(0.08, 0.05, 0.12) * half(glow);

    return half4(col, 1.0) * currentColor.a;
}

// MARK: - Pulsing ring effect for permission steps

[[ stitchable ]] half4 pulseRing(
    float2 position,
    half4 currentColor,
    float2 size,
    float time
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);

    // Expanding rings
    float ring1 = smoothstep(0.01, 0.0, abs(dist - fmod(time * 0.15, 0.6)));
    float ring2 = smoothstep(0.01, 0.0, abs(dist - fmod(time * 0.15 + 0.2, 0.6)));
    float ring3 = smoothstep(0.01, 0.0, abs(dist - fmod(time * 0.15 + 0.4, 0.6)));

    float rings = (ring1 + ring2 + ring3) * 0.3;

    half4 ringColor = half4(0.6, 0.3, 0.9, half(rings));
    return currentColor + ringColor * currentColor.a;
}
