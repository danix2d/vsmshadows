#ifndef VSM_SHADOWS_INCLUDED
#define VSM_SHADOWS_INCLUDED
#define ENABLE_BLUR

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D(_ShadowTex); 
SAMPLER(sampler_ShadowTex);

float4x4 _LightMatrix;
float4 _ShadowTexScale;

float _MaxShadowIntensity;
float _VarianceShadowExpansion;
float _BlurSize;

half SampleCustomShadow(float3 positionWS, float3 normalWS)
{
    // Transform world position to light's clip space
    float4 worldPos = float4(positionWS, 1.0);
    float4 lightSpacePos = mul(_LightMatrix, worldPos);
    
    // Convert normalWS to float4 for matrix multiplication
    float4 normalWS4 = float4(normalWS, 0.0);
    float4 lightSpaceNorm4 = mul(_LightMatrix, mul(unity_ObjectToWorld, normalWS4));
    float2 lightSpaceNorm = normalize(lightSpaceNorm4.xy);

    // Normalize the light space position to obtain depth and UV coordinates
    float4 lightSpacePosNDC = lightSpacePos / lightSpacePos.w;
    float depth = lightSpacePos.z / _ShadowTexScale.z;
    float2 shadowBias = lightSpaceNorm * _ShadowTexScale.w;
   // shadowBias *= 0.3;
    // Compute UV coordinates for shadow texture
    float2 uv = lightSpacePos.xy;
    uv += _ShadowTexScale.xy / 2;
    uv /= _ShadowTexScale.xy;

    // Check if UV coordinates are outside the valid range
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        return 1.0; // Return 1.0 (no shadow) if outside the shadow map bounds
    }
    #ifdef ENABLE_BLUR
        // Box blur sampling
        float2 blurOffset = _BlurSize * 0.2 / _ShadowTexScale.xy;

        float4 shadowMap = float4(0,0,0,0);

        float weight = 1.0 / 4.0;
        shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(-1.5, 0.5)) * weight;
        shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(0.5, 0.5)) * weight;
        shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(-1.5, -1.5)) * weight;
        shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(0.5, -1.5)) * weight;

        // float weight = 1.0 / 6.0;
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(1.0, 0.0)) * weight; // Center-left
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(1.0, 1.0)) * weight;  // Center-right
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(-1.0, 1.0)) * weight; // Bottom-left
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(-1.0, -1.0)) * weight;  // Bottom-center
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(0.0, -1.0)) * weight;  // Bottom-right
        // shadowMap += SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias + blurOffset * float2(0.0, 1.0)) * weight;  // Bottom-right

    #else
        float4 shadowMap = SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, uv + shadowBias);
    #endif

    
    // Extract variance data from shadow map
    float2 s = shadowMap.rg;
    float x = s.r;
    float x2 = s.g;

    // Calculate variance
    float var = x2 - x * x * 0.999;

    // Calculate the probability of being lit
    float p = depth <= x;

    // Calculate the upper bound of the probability using Chebyshev's inequality
    float delta = depth - x;
    float p_max = var / (var + delta * delta);

    // Alleviate light bleeding by expanding shadows
    float amount = _VarianceShadowExpansion;
    p_max = clamp((p_max - amount) / (1 - amount), 0, 1);

    // Final shadow intensity calculation
   float shadowIntensity = max(p, p_max);

    // float shadowIntensity = shadowMap.r < depth - 0.00025 ? 0.0 : 1.0;

    // Calculate distance to UV edges
    float2 edgeDistance = min(uv, 1.0 - uv);
    float minEdgeDistance = min(edgeDistance.x, edgeDistance.y);
    
    // Calculate fade factor based on distance to UV edges
    float fadeFactor = minEdgeDistance / 0.1; // You can adjust the 0.1 to control the fade range
    fadeFactor = clamp(fadeFactor, 0.0, 1.0);
    fadeFactor = 1 - fadeFactor;
    // Apply fade factor to shadow intensity
    shadowIntensity = lerp(1.0, shadowIntensity, _MaxShadowIntensity);
    shadowIntensity = lerp(shadowIntensity, 1.0, fadeFactor);

    return shadowIntensity;
}

#endif
