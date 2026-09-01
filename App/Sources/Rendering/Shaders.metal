#include <metal_stdlib>
using namespace metal;

struct VolumeUniforms {
    float4x4 inverseViewProjection;
    float4x4 planeToLocal;
    float3 cameraLocal;
    float stepMM;
    float3 halfExtentMM;
    float windowLow;
    float3 voxelStepTexture;
    float windowWidth;
    float3 tintColor;
    float opacityScale;
    float3 lightDirection;
    float surfaceThreshold;
    float surfaceSoftness;
    float maximumSteps;
    float ambient;
    float crossSectionAlpha;
    float3 clipPlanePoint;
    float clipEnabled;
    float3 clipPlaneNormal;
    float crossSectionAirHU;
    float globalAlpha;
    float emptyAlpha;
    float panoPointCount;
    float panoSlabMM;
    float shadingEnabled;
    float mipEnabled;
    float reservedA;
    float reservedB;
};

struct FullscreenVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVertex fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    FullscreenVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = corner;
    return out;
}

static inline float sampleHounsfield(texture3d<float, access::sample> volume,
                                     sampler volumeSampler,
                                     float3 coordinate) {
    return volume.sample(volumeSampler, coordinate).r * 32767.0;
}

static inline float normalizedDensity(float hounsfield, float low, float width) {
    return saturate((hounsfield - low) / width);
}

static bool intersectBox(float3 origin, float3 direction, float3 halfExtent,
                         thread float &nearT, thread float &farT) {
    float3 inverseDirection = 1.0 / direction;
    float3 firstPlane = (-halfExtent - origin) * inverseDirection;
    float3 secondPlane = (halfExtent - origin) * inverseDirection;
    float3 smaller = min(firstPlane, secondPlane);
    float3 larger = max(firstPlane, secondPlane);
    nearT = max(max(smaller.x, smaller.y), smaller.z);
    farT = min(min(larger.x, larger.y), larger.z);
    nearT = max(nearT, 0.0);
    return farT > nearT;
}

static inline float3 gradientNormal(texture3d<float, access::sample> volume,
                                    sampler volumeSampler,
                                    float3 coordinate,
                                    float3 step) {
    float dx = volume.sample(volumeSampler, coordinate + float3(step.x, 0.0, 0.0)).r
             - volume.sample(volumeSampler, coordinate - float3(step.x, 0.0, 0.0)).r;
    float dy = volume.sample(volumeSampler, coordinate + float3(0.0, step.y, 0.0)).r
             - volume.sample(volumeSampler, coordinate - float3(0.0, step.y, 0.0)).r;
    float dz = volume.sample(volumeSampler, coordinate + float3(0.0, 0.0, step.z)).r
             - volume.sample(volumeSampler, coordinate - float3(0.0, 0.0, step.z)).r;
    float3 gradient = float3(dx, dy, dz);
    float magnitude = length(gradient);
    if (magnitude < 1e-6) {
        return float3(0.0, 0.0, 1.0);
    }
    return -gradient / magnitude;
}

fragment float4 volumeRayMarchFragment(FullscreenVertex in [[stage_in]],
                                       constant VolumeUniforms &uniforms [[buffer(0)]],
                                       texture3d<float, access::sample> volume [[texture(0)]]) {
    constexpr sampler volumeSampler(filter::linear, address::clamp_to_edge, coord::normalized);

    float2 ndc = float2(in.uv.x * 2.0 - 1.0, in.uv.y * 2.0 - 1.0);
    float4 nearPoint = uniforms.inverseViewProjection * float4(ndc, 0.0, 1.0);
    float4 farPoint = uniforms.inverseViewProjection * float4(ndc, 1.0, 1.0);
    float3 origin = nearPoint.xyz / nearPoint.w;
    float3 direction = normalize(farPoint.xyz / farPoint.w - origin);

    float nearT = 0.0;
    float farT = 0.0;
    float3 halfExtent = uniforms.halfExtentMM;
    if (!intersectBox(origin, direction, halfExtent, nearT, farT)) {
        return float4(0.0);
    }

    if (uniforms.clipEnabled > 0.5) {
        float facing = dot(direction, uniforms.clipPlaneNormal);
        float toPlane = dot(uniforms.clipPlanePoint - origin, uniforms.clipPlaneNormal);
        if (facing < -1e-5) {
            nearT = max(nearT, toPlane / facing);
        } else if (toPlane > 0.0) {
            return float4(0.0, 0.0, 0.0, uniforms.emptyAlpha);
        }
        if (nearT >= farT) {
            return float4(0.0, 0.0, 0.0, uniforms.emptyAlpha);
        }
    }

    float3 accumulated = float3(0.0);
    float transmittance = 1.0;
    float travelled = nearT;
    float3 tint = uniforms.tintColor;
    float3 light = normalize(uniforms.lightDirection);
    float3 voxelStep = uniforms.voxelStepTexture;
    int limit = int(uniforms.maximumSteps);
    bool mip = uniforms.mipEnabled > 0.5;
    bool shading = uniforms.shadingEnabled > 0.5;
    float peak = -32768.0;

    for (int step = 0; step < limit; ++step) {
        if (travelled >= farT || (!mip && transmittance < 0.01)) {
            break;
        }
        float3 position = origin + direction * travelled;

        float3 coordinate = (position + halfExtent) / (2.0 * halfExtent);
        float hounsfield = sampleHounsfield(volume, volumeSampler, coordinate);
        if (mip) {
            peak = max(peak, hounsfield);
            travelled += uniforms.stepMM;
            continue;
        }
        float coverage = smoothstep(uniforms.surfaceThreshold - uniforms.surfaceSoftness,
                                    uniforms.surfaceThreshold + uniforms.surfaceSoftness,
                                    hounsfield);
        if (coverage > 0.001) {
            float alpha = 1.0 - pow(max(1.0 - coverage * uniforms.opacityScale, 0.0), uniforms.stepMM);
            float3 shaded = tint;
            if (shading) {
                float3 normal = gradientNormal(volume, volumeSampler, coordinate, voxelStep);
                float diffuse = max(dot(normal, light), 0.0);
                float3 halfway = normalize(light - direction);
                float specular = pow(max(dot(normal, halfway), 0.0), 28.0) * 0.35;
                shaded = tint * (uniforms.ambient + (1.0 - uniforms.ambient) * diffuse) + specular;
            }
            accumulated += transmittance * alpha * shaded;
            transmittance *= (1.0 - alpha);
        }
        travelled += uniforms.stepMM;
    }

    if (mip) {
        float intensity = normalizedDensity(peak, uniforms.windowLow, uniforms.windowWidth);
        float alpha = max(intensity * uniforms.globalAlpha, uniforms.emptyAlpha);
        return float4(float3(intensity) * uniforms.globalAlpha, alpha);
    }

    float coverageAlpha = (1.0 - transmittance) * uniforms.globalAlpha;
    return float4(accumulated * uniforms.globalAlpha, max(coverageAlpha, uniforms.emptyAlpha));
}

fragment float4 crossSectionFragment(FullscreenVertex in [[stage_in]],
                                     constant VolumeUniforms &uniforms [[buffer(0)]],
                                     texture3d<float, access::sample> volume [[texture(0)]]) {
    constexpr sampler volumeSampler(filter::linear, address::clamp_to_edge, coord::normalized);

    float2 plane = float2(in.uv.x * 2.0 - 1.0, in.uv.y * 2.0 - 1.0);
    float3 local = (uniforms.planeToLocal * float4(plane, 0.0, 1.0)).xyz;
    float3 halfExtent = uniforms.halfExtentMM;

    float3 outside = abs(local) - halfExtent;
    if (max(max(outside.x, outside.y), outside.z) > 0.0) {
        return float4(0.0);
    }

    float3 coordinate = (local + halfExtent) / (2.0 * halfExtent);
    float hounsfield = sampleHounsfield(volume, volumeSampler, coordinate);
    float intensity = normalizedDensity(hounsfield, uniforms.windowLow, uniforms.windowWidth);
    float edge = 1.0 - smoothstep(-1.2, 0.0, max(max(outside.x, outside.y), outside.z));
    float tissue = smoothstep(uniforms.crossSectionAirHU - 250.0, uniforms.crossSectionAirHU + 250.0, hounsfield);

    return float4(float3(intensity), uniforms.crossSectionAlpha * edge * tissue);
}

fragment float4 panoramicFragment(FullscreenVertex in [[stage_in]],
                                  constant VolumeUniforms &uniforms [[buffer(0)]],
                                  constant float3 *archPoints [[buffer(1)]],
                                  texture3d<float, access::sample> volume [[texture(0)]]) {
    constexpr sampler volumeSampler(filter::linear, address::clamp_to_edge, coord::normalized);

    int count = int(uniforms.panoPointCount);
    if (count < 2) {
        return float4(0.0);
    }

    float arc = clamp(in.uv.x, 0.0, 1.0) * float(count - 1);
    int index = min(int(arc), count - 2);
    float fraction = arc - float(index);
    float3 base = mix(archPoints[index], archPoints[index + 1], fraction);
    float3 tangent = archPoints[index + 1] - archPoints[index];
    float2 flat = float2(tangent.x, tangent.y);
    float flatLength = length(flat);
    float2 normal2 = flatLength > 1e-5 ? float2(-flat.y, flat.x) / flatLength : float2(0.0, 0.0);

    float3 halfExtent = uniforms.halfExtentMM;
    float z = (in.uv.y * 2.0 - 1.0) * halfExtent.z;

    float total = 0.0;
    float weight = 0.0;
    int slabSamples = uniforms.panoSlabMM > 0.01 ? 5 : 1;
    for (int sampleIndex = 0; sampleIndex < slabSamples; ++sampleIndex) {
        float offset = slabSamples > 1
            ? (float(sampleIndex) / float(slabSamples - 1) - 0.5) * 2.0 * uniforms.panoSlabMM
            : 0.0;
        float3 position = float3(base.x + normal2.x * offset, base.y + normal2.y * offset, z);
        float3 outside = abs(position) - halfExtent;
        if (max(max(outside.x, outside.y), outside.z) > 0.0) {
            continue;
        }
        float3 coordinate = (position + halfExtent) / (2.0 * halfExtent);
        total += sampleHounsfield(volume, volumeSampler, coordinate);
        weight += 1.0;
    }
    if (weight < 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float intensity = normalizedDensity(total / weight, uniforms.windowLow, uniforms.windowWidth);
    return float4(float3(intensity), 1.0);
}

struct CameraVertex {
    float4 position [[position]];
    float2 uv;
};

vertex CameraVertex cameraBackgroundVertex(uint vertexID [[vertex_id]],
                                           constant float4x4 &transform [[buffer(0)]]) {
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    CameraVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    float2 viewCoordinate = float2(corner.x, 1.0 - corner.y);
    float4 mapped = transform * float4(viewCoordinate, 0.0, 1.0);
    out.uv = mapped.xy;
    return out;
}

fragment float4 cameraBackgroundFragment(CameraVertex in [[stage_in]],
                                         texture2d<float, access::sample> luma [[texture(0)]],
                                         texture2d<float, access::sample> chroma [[texture(1)]]) {
    constexpr sampler videoSampler(filter::linear, address::clamp_to_edge, coord::normalized);
    float y = luma.sample(videoSampler, in.uv).r;
    float2 cbcr = chroma.sample(videoSampler, in.uv).rg - float2(0.5, 0.5);
    float3 rgb;
    rgb.r = y + 1.402 * cbcr.y;
    rgb.g = y - 0.344136 * cbcr.x - 0.714136 * cbcr.y;
    rgb.b = y + 1.772 * cbcr.x;
    return float4(rgb, 1.0);
}
