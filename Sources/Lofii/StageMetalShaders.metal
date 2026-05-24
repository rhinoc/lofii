#include <metal_stdlib>

using namespace metal;

struct StageVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct StageUniforms {
    float2 viewportSize;
    float2 sourceSize;
    float curvationFactor;
    float opacity;
    float overscan;
    float scanlineAmount;
    float scanlinePitch;
    float borderSize;
    float vignetteAlpha;
    float motionBlurStrength;
    float chromaticAberrationStrength;
    float zfastBlurScaleX;
    float zfastLowLumScan;
    float zfastHighLumScan;
    float zfastBrightBoost;
    float zfastMaskDark;
    float zfastMaskFade;
    float glassOpacity;
    float glassRefractionPixels;
    float glassHighlightStrength;
    float glassFlipX;
    float2 glassTextureSize;
};

vertex StageVertexOut stageVertex(uint vertexID [[vertex_id]])
{
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };

    const float2 p = positions[vertexID];
    StageVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
    return out;
}

static float screenRadius(float2 uv)
{
    const float2 c = uv - 0.5;
    return sqrt(dot(c, c));
}

static float2 screenZoom(float2 uv, float f)
{
    return float2(
        uv.x - (uv.x - 0.5) * f,
        uv.y - (uv.y - 0.5) * f
    );
}

static float2 screenDistort(float2 uv, float f)
{
    return screenZoom(uv, screenRadius(uv) * f);
}

static float screenBorder(float p, float f)
{
    return clamp(-abs((p - 0.5) / f) + (0.5 / f) + 1.0, 0.0, 1.0);
}

static float crtApertureDarkness(float2 uv)
{
    const float2 p = uv * 2.0 - 1.0;
    const float ax = abs(p.x);
    const float ay = abs(p.y);
    const float ax2 = ax * ax;
    const float ay2 = ay * ay;

    // Mega-Bezel style layering: first define the visible tube aperture as a
    // bowed rectangle, then add only a narrow glass falloff near that edge.
    const float verticalLimit =
        0.955 - 0.022 * ax2 - 0.040 * ax2 * ax2 - 0.014 * ax2 * ax2 * ax2;
    const float horizontalLimit =
        0.992 - 0.010 * ay2 - 0.024 * ay2 * ay2 - 0.010 * ay2 * ay2 * ay2;

    const float edgeY = (ay - verticalLimit) / 0.055;
    const float edgeX = (ax - horizontalLimit) / 0.050;
    const float apertureEdge = max(edgeX, edgeY);
    const float apertureMask = smoothstep(-0.70, 0.25, apertureEdge);

    const float cornerCompression = smoothstep(0.78, 0.98, ax * ay);
    const float glassEdge = smoothstep(-1.65, -0.18, apertureEdge);
    const float cornerGlass = smoothstep(1.54, 1.92, ax + ay);

    return clamp(
        apertureMask * 0.92 +
        glassEdge * 0.10 +
        cornerCompression * 0.08 +
        cornerGlass * 0.10,
        0.0,
        1.0
    );
}

static float2 aspectFillUV(float2 viewportUV, float2 viewportSize, float2 sourceSize)
{
    const float scale = max(viewportSize.x / sourceSize.x, viewportSize.y / sourceSize.y);
    const float2 drawnSize = sourceSize * scale;
    const float2 offset = (viewportSize - drawnSize) * 0.5;
    const float2 sourcePx = (viewportUV * viewportSize - offset) / scale;
    return clamp(sourcePx / sourceSize, 0.0, 1.0);
}

static float2 aspectFillDrawnSize(float2 viewportSize, float2 sourceSize)
{
    const float scale = max(viewportSize.x / sourceSize.x, viewportSize.y / sourceSize.y);
    return max(sourceSize * scale, float2(1.0));
}

static float2 aspectFillSourceUV(float2 viewportUV, constant StageUniforms& uniforms)
{
    const float2 viewportSize = max(uniforms.viewportSize, float2(1.0));
    const float2 sourceSize = max(uniforms.sourceSize, float2(1.0));
    return aspectFillUV(viewportUV, viewportSize, sourceSize);
}

static float2 aspectFillDrawnSizeForUniforms(constant StageUniforms& uniforms)
{
    const float2 viewportSize = max(uniforms.viewportSize, float2(1.0));
    const float2 sourceSize = max(uniforms.sourceSize, float2(1.0));
    return aspectFillDrawnSize(viewportSize, sourceSize);
}

static half4 sampleSource(
    texture2d<half, access::sample> sourceTexture,
    sampler sourceSampler,
    float2 sourceUV
) {
    return sourceTexture.sample(sourceSampler, clamp(sourceUV, 0.0, 1.0));
}

static half4 sampleSourceWithMotionBlur(
    texture2d<half, access::sample> sourceTexture,
    sampler sourceSampler,
    float2 sourceUV,
    constant StageUniforms& uniforms
) {
    if (uniforms.motionBlurStrength <= 0.0001) {
        return sampleSource(sourceTexture, sourceSampler, sourceUV);
    }

    const float2 drawnSize = aspectFillDrawnSizeForUniforms(uniforms);
    const float2 blurStep = float2(9.0, 3.0) * uniforms.motionBlurStrength / drawnSize;
    half4 color = sampleSource(sourceTexture, sourceSampler, sourceUV) * half(0.38);
    color += sampleSource(sourceTexture, sourceSampler, sourceUV - blurStep) * half(0.22);
    color += sampleSource(sourceTexture, sourceSampler, sourceUV + blurStep) * half(0.22);
    color += sampleSource(sourceTexture, sourceSampler, sourceUV - blurStep * 2.0) * half(0.09);
    color += sampleSource(sourceTexture, sourceSampler, sourceUV + blurStep * 2.0) * half(0.09);
    return color;
}

static float sourceLuma(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

static float3 ntscArtifact(float2 sourcePixel)
{
    const float stripe = floor(sourcePixel.x + sourcePixel.y * 0.5);
    const float phase = fmod(stripe, 3.0);
    float3 artifact = float3(0.25, 0.25, 0.25);
    artifact.r += (phase < 1.0) ? 0.75 : 0.0;
    artifact.g += (phase >= 1.0 && phase < 2.0) ? 0.75 : 0.0;
    artifact.b += (phase >= 2.0) ? 0.75 : 0.0;
    return artifact;
}

static float blendOverlay(float base, float blend)
{
    return base < 0.5
        ? 2.0 * base * blend
        : 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
}

static float3 blendOverlay(float3 base, float3 blend)
{
    return float3(
        blendOverlay(base.r, blend.r),
        blendOverlay(base.g, blend.g),
        blendOverlay(base.b, blend.b)
    );
}

static half4 applyNTSCChromaticAberration(
    texture2d<half, access::sample> sourceTexture,
    sampler sourceSampler,
    float2 viewportUV,
    float2 sourceUV,
    half4 baseColor,
    constant StageUniforms& uniforms
) {
    const float amount = clamp(uniforms.chromaticAberrationStrength, 0.0, 2.0);
    if (amount <= 0.0001) {
        return baseColor;
    }

    const float2 sourceSize = max(uniforms.sourceSize, float2(1.0));
    const float2 drawnSize = aspectFillDrawnSizeForUniforms(uniforms);
    const float2 displayPixelX = float2(1.0 / drawnSize.x, 0.0);
    const float3 artifact = ntscArtifact(sourceUV * sourceSize);
    const float edgeFade = smoothstep(0.0, 2.5 / drawnSize.x, min(sourceUV.x, 1.0 - sourceUV.x));

    const float3 baseRGB = float3(baseColor.rgb);
    const float3 leftRGB = float3(sampleSource(sourceTexture, sourceSampler, sourceUV - displayPixelX).rgb);
    const float3 rightRGB = float3(sampleSource(sourceTexture, sourceSampler, sourceUV + displayPixelX).rgb);
    float3 rgb = baseRGB + ((leftRGB - baseRGB) + (rightRGB - baseRGB)) * artifact * (0.42 * amount * edgeFade);

    float overshoot = 0.0;
    const float sharpWeights[3] = { 1.0, -0.3162277, 0.1 };
    const float localLuma = sourceLuma(baseRGB);
    for (uint i = 0; i < 3; ++i) {
        const float2 step = displayPixelX * float(i + 1);
        const float3 tapL = float3(sampleSource(sourceTexture, sourceSampler, sourceUV - step).rgb);
        const float3 tapR = float3(sampleSource(sourceTexture, sourceSampler, sourceUV + step).rgb);
        overshoot += ((localLuma - sourceLuma(tapL)) + (localLuma - sourceLuma(tapR))) * sharpWeights[i];
    }
    rgb += overshoot * mix(float3(1.0), artifact, clamp(amount, 0.0, 1.0)) * (0.10 * amount * edgeFade);

    const float splitPixels = 0.85 + 2.25 * amount;
    const float2 splitStep = displayPixelX * splitPixels;
    const float3 splitRGB = float3(
        sampleSource(sourceTexture, sourceSampler, sourceUV + splitStep).r,
        baseColor.g,
        sampleSource(sourceTexture, sourceSampler, sourceUV - splitStep).b
    );
    rgb = mix(rgb, splitRGB, clamp(0.24 * amount * edgeFade, 0.0, 0.58));

    const float2 centered = viewportUV - 0.5;
    const float radius = length(centered);
    const float radialWeight = smoothstep(0.08, 0.66, radius);
    const float2 radialDir = normalize(centered + float2(0.0001, 0.0));
    const float2 radialStep = radialDir * ((1.2 + 3.4 * amount) * radialWeight) / drawnSize;
    const float3 radialRGB = float3(
        sampleSource(sourceTexture, sourceSampler, sourceUV + radialStep).r,
        rgb.g,
        sampleSource(sourceTexture, sourceSampler, sourceUV - radialStep).b
    );
    rgb = mix(rgb, radialRGB, clamp(0.28 + 0.20 * amount, 0.0, 0.72) * radialWeight);

    return half4(half3(clamp(rgb, 0.0, 1.0)), baseColor.a);
}

static half4 applyShatteredGlass(
    texture2d<half, access::sample> sourceTexture,
    texture2d<half, access::sample> glassPatternTexture,
    texture2d<half, access::sample> glassBackgroundTexture,
    sampler sourceSampler,
    float2 viewportUV,
    float2 sourceUV,
    half4 baseColor,
    constant StageUniforms& uniforms
) {
    const float opacity = clamp(uniforms.glassOpacity, 0.0, 1.0);
    if (opacity <= 0.0001) {
        return baseColor;
    }

    const float2 sourceSize = max(uniforms.sourceSize, float2(1.0));
    const float2 viewportSize = max(uniforms.viewportSize, float2(1.0));
    const float flipX = step(0.5, uniforms.glassFlipX);
    const float2 glassTextureSize = max(uniforms.glassTextureSize, float2(1.0));
    const float2 fittedGlassUV = aspectFillUV(viewportUV, viewportSize, glassTextureSize);
    const float2 glassUV = clamp(float2(mix(fittedGlassUV.x, 1.0 - fittedGlassUV.x, flipX), fittedGlassUV.y), 0.0, 1.0);
    const half4 pattern = glassPatternTexture.sample(sourceSampler, glassUV);
    const half4 glassBackground = glassBackgroundTexture.sample(sourceSampler, glassUV);

    const float fracture = clamp(max(1.0 - float(pattern.a), float(glassBackground.a)), 0.0, 1.0);
    const float2 probeStep = float2(3.0, -3.0) / viewportSize;
    const float adjacentFracture = 1.0 - float(glassPatternTexture.sample(sourceSampler, clamp(glassUV + probeStep, 0.0, 1.0)).a);
    const float rim = clamp(max(fracture, adjacentFracture) - fracture * 0.35, 0.0, 1.0);

    const float2 shardVector = normalize((glassUV - 0.5) * float2(1.35, 1.0) + float2(0.10, -0.06));
    const float refractionMask = smoothstep(0.015, 0.88, max(fracture, float(glassBackground.a)));
    const float2 refractedUV = sourceUV + shardVector * (uniforms.glassRefractionPixels / sourceSize) * refractionMask;
    half4 color = sampleSource(sourceTexture, sourceSampler, refractedUV);

    const float3 baseRGB = float3(color.rgb);
    const float3 glassRGB = float3(glassBackground.rgb);
    const float3 overlaid = blendOverlay(baseRGB, glassRGB);
    const float overlayAlpha = clamp((float(glassBackground.a) * 0.72 + fracture * 0.26) * opacity, 0.0, 0.96);
    float3 rgb = mix(baseRGB, overlaid, overlayAlpha);

    const float highlight = clamp((rim * 0.72 + adjacentFracture * 0.18) * uniforms.glassHighlightStrength * opacity, 0.0, 0.85);
    rgb = clamp(rgb + highlight, 0.0, 1.0);
    return half4(half3(rgb), baseColor.a);
}

fragment half4 stageFragment(
    StageVertexOut in [[stage_in]],
    texture2d<half, access::sample> sourceTexture [[texture(0)]],
    texture2d<half, access::sample> glassPatternTexture [[texture(1)]],
    texture2d<half, access::sample> glassBackgroundTexture [[texture(2)]],
    constant StageUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.opacity <= 0.0) {
        return half4(0.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler sourceSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    float2 viewportUV = clamp(in.uv, 0.0, 1.0);
    viewportUV = (viewportUV - 0.5) / max(uniforms.overscan, 1.0) + 0.5;
    if (uniforms.curvationFactor > 0.0001) {
        viewportUV = screenDistort(viewportUV, -uniforms.curvationFactor);
    }

    if (viewportUV.x > 1.0 || viewportUV.x < 0.0 || viewportUV.y > 1.0 || viewportUV.y < 0.0) {
        if (uniforms.borderSize <= 0.0) {
            return half4(0.0, 0.0, 0.0, 1.0);
        }
        const float borderAlpha =
            screenBorder(viewportUV.x, uniforms.borderSize) *
            screenBorder(viewportUV.y, uniforms.borderSize);
        return half4(0.0, 0.0, 0.0, half(borderAlpha));
    }

    float2 sourceUV = aspectFillSourceUV(viewportUV, uniforms);
    const float2 sourceSize = max(uniforms.sourceSize, float2(1.0));
    float2 sourcePixel = sourceUV * sourceSize;
    const float2 sourceCenter = floor(sourcePixel) + 0.5;
    const float2 sourceDelta = sourcePixel - sourceCenter;
    const float2 sourceDelta2 = sourceDelta * sourceDelta;

    float2 zfastUV = (sourceCenter + 4.0 * sourceDelta * sourceDelta2) / sourceSize;
    zfastUV.x = mix(zfastUV.x, sourceUV.x, clamp(uniforms.zfastBlurScaleX, 0.0, 1.0));

    half4 color = sampleSourceWithMotionBlur(sourceTexture, sourceSampler, zfastUV, uniforms);
    color = applyNTSCChromaticAberration(sourceTexture, sourceSampler, viewportUV, zfastUV, color, uniforms);
    color = applyShatteredGlass(
        sourceTexture,
        glassPatternTexture,
        glassBackgroundTexture,
        sourceSampler,
        viewportUV,
        zfastUV,
        color,
        uniforms
    );

    if (uniforms.scanlineAmount > 0.0001) {
        const float pixelX = floor(in.uv.x * max(uniforms.viewportSize.x, 1.0));
        const float whichMask = pixelX * -0.5;
        const float mask =
            1.0 - ((fract(whichMask) < 0.5) ? uniforms.zfastMaskDark : 0.0);
        const float pixelY = in.uv.y * max(uniforms.viewportSize.y, 1.0);
        const float scanlinePitch = max(uniforms.scanlinePitch, 1.0);
        const float scanlinePhase = fract(pixelY / scanlinePitch);
        const float scanlineDistance = abs(scanlinePhase - 0.5) * 2.0;
        const float darkBand = 1.0 - smoothstep(0.18, 0.72, scanlineDistance);
        const float brightBand = smoothstep(0.55, 1.0, scanlineDistance) * 0.08;
        const float3 rgb = float3(color.rgb);
        const float lumaMix = clamp(dot(rgb, float3(0.3333 * uniforms.zfastMaskFade)), 0.0, 1.0);
        const float scanlineDarkness = mix(0.42, 0.26, lumaMix);
        const float scanlineWeight = 1.0 - darkBand * scanlineDarkness + brightBand;
        const float maskWeight = mix(1.0, mask, 0.42);
        const float3 zfastRGB = clamp(rgb * scanlineWeight * maskWeight, 0.0, 1.0);
        const float amount = clamp(uniforms.scanlineAmount * 1.55, 0.0, 1.0);
        color.rgb = half3(mix(rgb, zfastRGB, amount));
    }

    if (uniforms.vignetteAlpha > 0.0001) {
        const float darkness = crtApertureDarkness(in.uv);
        const float strength = clamp(uniforms.vignetteAlpha * 1.65, 0.0, 1.0);
        color.rgb *= half(max(0.0, 1.0 - darkness * strength));
    }

    return color;
}

struct BongoQuadUniforms {
    float2 viewportSize;
    float2 rectOrigin;
    float2 rectSize;
    float opacity;
};

struct BongoMaskUniforms {
    float4 color;
    float2 viewportSize;
    float leftY;
    float rightY;
};

vertex StageVertexOut bongoQuadVertex(
    uint vertexID [[vertex_id]],
    constant BongoQuadUniforms& uniforms [[buffer(0)]]
) {
    const float2 corners[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0),
    };

    const float2 viewport = max(uniforms.viewportSize, float2(1.0));
    const float2 c = corners[vertexID];
    const float2 pixel = uniforms.rectOrigin + c * uniforms.rectSize;
    const float2 clip = float2(
        pixel.x / viewport.x * 2.0 - 1.0,
        1.0 - pixel.y / viewport.y * 2.0
    );

    StageVertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.uv = c;
    return out;
}

fragment half4 bongoTextureFragment(
    StageVertexOut in [[stage_in]],
    texture2d<half, access::sample> sourceTexture [[texture(0)]],
    constant BongoQuadUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler sourceSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );
    half4 color = sourceTexture.sample(sourceSampler, clamp(in.uv, 0.0, 1.0));
    color.a *= half(clamp(uniforms.opacity, 0.0, 1.0));
    color.rgb *= color.a;
    return color;
}

fragment half4 bongoDesktopMaskFragment(
    StageVertexOut in [[stage_in]],
    constant BongoMaskUniforms& uniforms [[buffer(0)]]
) {
    const float y = in.uv.y * max(uniforms.viewportSize.y, 1.0);
    const float lineY = mix(uniforms.leftY, uniforms.rightY, clamp(in.uv.x, 0.0, 1.0));
    const float signedDistance = y - lineY;
    const bool fullCoverageMask = uniforms.leftY <= 0.0 && uniforms.rightY <= 0.0;
    const float edgeWidth = max(fwidth(signedDistance), 1.0);
    const float coverage = fullCoverageMask ? 1.0 : smoothstep(-edgeWidth, edgeWidth, signedDistance);
    const float alpha = uniforms.color.a * coverage;
    return half4(half3(uniforms.color.rgb * alpha), half(alpha));
}
