//
//  DisperseMetalEffect.metal
//  DisperseEffect
//
//  Created by Balaji Venkatesh on 15/06/26.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static inline float hash21(float2 point) {
    point = fract(point * float2(123.34, 456.21));
    point += dot(point, point + 45.32);
    return fract(point.x * point.y);
}

/// Direction: 0 = left→right
/// 1 = right→left
/// 2 = top→bottom
/// 3 = bottom→top

/// Count: Disperse Particle Count
[[ stitchable ]] half4 disperseEffect(
     float2 position,
     SwiftUI::Layer layer,
     float2 size,
     float progress,
     float count,
     float direction
) {
    if (progress <= 0.0) {
        return layer.sample(position);
    }

    float2 normalizedPosition = position / size;
    float2 cell = floor(normalizedPosition * count) / count;
    float2 cellCenter = cell + 0.5 / count;

    float randomValue = hash21(cell * 17.0 + 3.7);
    float randomSign = hash21(cell * 91.3) * 2.0 - 1.0;

    float waveAxis = cellCenter.x;
    if (direction == 1.0) {
        waveAxis = 1.0 - cellCenter.x;
    } else if (direction == 2.0) {
        waveAxis = cellCenter.y;
    } else if (direction == 3.0) {
        waveAxis = 1.0 - cellCenter.y;
    }

    //float waveFront = progress * 1.6 - 0.3;
    float waveFront = progress * 2.2 - 0.4;
    float flakeProgress = saturate((waveFront - waveAxis) * 2.5 + randomValue * 0.6);

    if (flakeProgress <= 0.0) {
        return layer.sample(position);
    }

    float mainDirectionY = -1.0;
    if (direction == 2.0) {
        mainDirectionY = 1.0;
    }

    float driftAmount = flakeProgress * flakeProgress;
    float mainMagnitude = (0.25 + randomValue * 0.35) * driftAmount;
    float wobbleMagnitude = randomSign * 0.15 * driftAmount;

    float2 offset;
    offset.x = wobbleMagnitude * size.x;
    offset.y = mainDirectionY * mainMagnitude * size.y;

    float alpha = (1.0 - flakeProgress) * (1.0 - flakeProgress);
    if (alpha <= 0.001) {
        return half4(0.0);
    }

    return layer.sample(position - offset) * half(alpha);
}
