cbuffer cbCamera : register(b0) {
  float4x4 gView;
  float4x4 gProjection;
  float4x4 gViewProjectionInverse;
  float3 gCameraShiftedPosition;
  float gCameraFOVValue;
  float gNearPlane;
  float gFarPlane;
  float2 _pad0C;
}

float2 __loadVector(uint v) { return float2(f16tof32(v), f16tof32(v >> 16)); }
float4 __loadVector(uint2 v) { return float4(__loadVector(v.x), __loadVector(v.y)); }

cbuffer cbLighting : register(b2) {  
  float3 gLightDirection;
  float _pad7;

  float3 gAmbientColor;
  float _pad8;

  float3 gLightColor;
  float _pad9;

  float4 _pad0;
  float4 _pad1;
  float3 _pad2;
  float gFogLinear;

  float gFogBlend;
  float3 gFogColor;

  float4 _pad3;
  float4 _pad4;

  float4 _pad5;
  float3 _pad6;
  #ifdef __USE_GAMMA_FIX
    uint _pad6_0;
    #define gUseNewFog 1
    #define USE_LINEAR_COLOR_SPACE 1
  #else
    uint gUseNewFog;
    #define USE_LINEAR_COLOR_SPACE 0
  #endif

  float gFogConstantPiece; 
  float gFogBacklitMult;
  float gFogBacklitExp;
  float gFogExp;

  float3 gAdditionalAmbientColor;
  float _pad10;
  
  float3 gAdditionalAmbientDir;
  float _pad11;

  float3 gBaseAmbient;
  float _pad12;

  float3 gSpecularColor;
  #ifdef __USE_GAMMA_FIX
    uint _pad12_0;
    #define gSunSpecularMult 1
  #else
    float gSunSpecularMult;
  #endif

  float4 _pad13;

  uint _pad14_0;
  uint _pad14_1;
  uint _extGlowBrightness_extForceEmissive;
  float _extLambertGamma_inner;
  #ifdef __USE_GAMMA_FIX
    #define extLambertGamma 1.
    #define gMainBrightnessMult _extLambertGamma_inner
  #else
    #define extLambertGamma _extLambertGamma_inner
    #define gMainBrightnessMult 1.
  #endif
  #define gGlowBrightness (__loadVector(_extGlowBrightness_extForceEmissive).x)
  #define gForceEmissive (__loadVector(_extGlowBrightness_extForceEmissive).y)

  float4 gEmissiveMults; // emissive mult, emissive mult×adaptive mult nearby, emissive mult×adaptive mult distant, white ref emissive
  #define gWhiteRefPoint gEmissiveMults.w

  float _extIBLAmbient;
  float _extIBLAmbientBaseThreshold;  
  float _extIBLAmbientBrightness;
  float _extIBLAmbientSaturation;
  #ifdef __USE_GAMMA_FIX
    #define p_fog2Color_blend asuint(float2(_extIBLAmbient, _extIBLAmbientBaseThreshold))
    #define p_fog2Exp _extIBLAmbientBrightness
    #define p_fog2Linear _extIBLAmbientSaturation
  #endif

  float3 _pad17;
  float extCloudShadowOpacity;

  float4x4 extCloudShadowMatrix;
  float4 _pad19;

  float3 gCameraDirLook;
  float gFogAtmosphere;

  float3 gCameraDirUp;
  uint _pad20;

  float3 gSceneOffset;
  float _pad22;

  float2 _pad23;
  uint __extWfxHint01;
  float _pad24;

  float3 __ksAmbientColor_sky1;
  float __ksAmbientColor_sky1_mix;

  float3 __extExtraAoAmbientColor;
  float __extExtraAoAmbientColor_exp;
}

#define gCameraPosition (gCameraShiftedPosition - gSceneOffset)

float linearizeDepth(float depth){
  return 2 * gNearPlane * gFarPlane / (gFarPlane + gNearPlane - (2 * depth - 1) * (gFarPlane - gNearPlane));
}

float delinearizeDepth(float linearDepth){
  return (gFarPlane + gNearPlane - 2 * gNearPlane * gFarPlane / linearDepth) / (gFarPlane - gNearPlane) / 2 + 0.5;
}

float getCloudShadow(float3 posC){
  return saturate(1 - txCloudShadow__.SampleLevel(samLinearClamp, mul(float4(posC, 1), extCloudShadowMatrix).xy, 0) * extCloudShadowOpacity);
}

float3 toLinearColorSpace(float3 color) {
  return USE_LINEAR_COLOR_SPACE ? pow(max(color, 0), 2.2) : color;
}

float3 toSrgbColorSpace(float3 color) {
  return USE_LINEAR_COLOR_SPACE ? pow(max(color, 0), 1 / 2.2) : color;
}

float convertHDR(float input, bool toHDR = false) {
  #ifdef __USE_GAMMA_FIX
    float2 p = asuint(__extWfxHint01);
    input = toHDR ? pow(max(0, input), 1.f / p.y) / p.x : pow(max(input * p.x, 0), p.y);
  #endif
  return input;
}

float2 convertHDR(float2 input, bool toHDR = false) {
  #ifdef __USE_GAMMA_FIX
    float2 p = asuint(__extWfxHint01);
    input = toHDR ? pow(max(0, input), 1.f / p.y) / p.x : pow(max(input * p.x, 0), p.y);
  #endif
  return input;
}

float3 convertHDR(float3 input, bool toHDR = false) {
  #ifdef __USE_GAMMA_FIX
    float2 p = asuint(__extWfxHint01);
    input = toHDR ? pow(max(0, input), 1.f / p.y) / p.x : pow(max(input * p.x, 0), p.y);
  #endif
  return input;
}

float4 convertHDR(float4 input, bool toHDR = false) {
  #ifdef __USE_GAMMA_FIX
    float2 p = asuint(__extWfxHint01);
    input = toHDR ? pow(max(0, input), 1.f / p.y) / p.x : pow(max(input * p.x, 0), p.y);
  #endif
  return input;
}