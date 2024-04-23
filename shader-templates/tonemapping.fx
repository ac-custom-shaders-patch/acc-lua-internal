/* Template for custom tonemapping functions */

float2 fParam_DepthCastScaleOffset;
float4 fParam_DepthOfFieldFactorScaleOffset;
float4 fParam_HDRFormatFactor_LOGRGB;
float4 fParam_HDRFormatFactor_RGBALUM;
float4 fParam_HDRFormatFactor_REINHARDRGB;
float2 fParam_ScreenSpaceScale;
float4x4 m44_ModelViewProject;
float4 vParam_LensDistortion;
float4 afUVWQ_TexCoordScaleOffset[4];
float4 fParam_PerspectiveFactor;
float fParam_FocusDistance;
float4 fParam_DepthOfFieldConvertDepthFactor;
float2 afXY_DepthOfFieldLevelBlendFactor16[16];
float fParam_DepthOfFieldLayerMaskThreshold;
float fParam_DepthOfFieldFactorThreshold;
float4 afUV_TexCoordOffsetV16[16];
float4 afUV_TexCoordOffsetP32[96];
float4 afParam_TexCoordScaler8[8];
float4 afRGBA_Modulate[32];
float4 afRGBA_Offset[16];
float fParam_GammaCorrection;
float2 fParam_DitherOffsetScale;
float4 fRGBA_Constant;
float4 afRGBA_Constant[4];
float4 fParam_TonemapMaxMappingLuminance;
float4 fParam_BrightPassRemapFactor;
float4 m44_ColorTransformMatrix[4];
float4 m44_PreTonemapColorTransformMatrix[4];
float4 m44_PreTonemapGlareColorTransformMatrix[4];
float4 fParam_VignetteSimulate;
float fParam_VignettePowerOfCosine;
float4x4 am44_TransformMatrix[8];

Texture2D<float4> atex2D_Texture[4] : register(t0);
SamplerState asamp2D_Texture[4] : register(s0);

SamplerState samLinearSimple : register(s5) { Filter = LINEAR; AddressU = WRAP; AddressV = WRAP;};
SamplerState samLinearBorder0 : register(s6) { Filter = MIN_MAG_MIP_LINEAR; AddressU = BORDER; AddressV = BORDER; AddressW = BORDER; BorderColor = (float4)0;};
SamplerState samLinearBorder1 : register(s7) { Filter = MIN_MAG_MIP_LINEAR; AddressU = Border; AddressV = Border; AddressW = Border; BorderColor = (float4)1;};
SamplerState samLinearClamp : register(s8) { Filter = MIN_MAG_MIP_LINEAR; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP;};
SamplerState samPointClamp : register(s9) { Filter = POINT; AddressU = CLAMP; AddressV = CLAMP;};
SamplerState samPointBorder0 : register(s10) { Filter = POINT; AddressU = CLAMP; AddressV = CLAMP;};
SamplerState samAnisotropic : register(s11) { Filter = LINEAR; AddressU = WRAP; AddressV = WRAP;};
SamplerState samAnisotropicClamp : register(s12) { Filter = LINEAR; AddressU = CLAMP; AddressV = CLAMP;};
#define samLinear samLinearSimple
#define samPoint samPointClamp

struct PS_INPUT {
  float4 TEXCOORD0 : TEXCOORD0;
  float4 TEXCOORD1 : TEXCOORD1;
  float4 TEXCOORD2 : TEXCOORD2;
  float4 TEXCOORD3 : TEXCOORD3;
  float4 TEXCOORD4 : TEXCOORD4;
};

struct PS_OUTPUT {
  float4 SV_TARGET : SV_TARGET;
};

$DEFINES~
$TEXTURES~

#ifdef __USE_GAMMA_FIX
  #define USE_LINEAR_COLOR_SPACE 1
#else
  #define USE_LINEAR_COLOR_SPACE 0
#endif

cbuffer cbData : register(b1) { 
  $VALUES~
}

$CODE~

PS_OUTPUT entryPoint(PS_INPUT input) {
  float2 TEXCOORD0 = input.TEXCOORD0.xy;
  float2 TEXCOORD1 = input.TEXCOORD1.xy;
  float2 TEXCOORD2 = input.TEXCOORD2.xy;
  float2 TEXCOORD3 = input.TEXCOORD3.xy;
  float2 TEXCOORD4 = input.TEXCOORD4.xy;
  PS_OUTPUT output;
  float r0x = dot(TEXCOORD2, TEXCOORD2);
  float r0y = r0x + 1;
  r0x = saturate(r0y - 2 * r0x);
  r0x = r0x * r0x;
  r0x = r0x * r0x;
  float4 r1_xyzw = atex2D_Texture[2].Sample(asamp2D_Texture[2], TEXCOORD3);
  float3 r0_yzw = r1_xyzw.xyz * afRGBA_Offset[0].x + afRGBA_Offset[0].y;
  r1_xyzw.xyz = r1_xyzw.xyz * afRGBA_Offset[2].x + afRGBA_Offset[2].y;
  r1_xyzw.w = dot(r0_yzw, 1/3.);
  r0_yzw = r0_yzw - r1_xyzw.w;
  r0_yzw = saturate(afRGBA_Offset[1].x * r0_yzw + r1_xyzw.w);
  r0_yzw = r0_yzw * afRGBA_Offset[0].z + afRGBA_Offset[0].w;
  r1_xyzw.w = dot(r1_xyzw.xyz, 1/3.);
  r1_xyzw.xyz = r1_xyzw.xyz - r1_xyzw.w;
  r1_xyzw.xyz = afRGBA_Offset[3].x * r1_xyzw.xyz + r1_xyzw.w;
  r1_xyzw.xyz = r1_xyzw.xyz * afRGBA_Offset[2].z + afRGBA_Offset[2].w;
  float4 r2_xyzw = atex2D_Texture[1].Sample(asamp2D_Texture[1], TEXCOORD1);
  r2_xyzw.xyz = r2_xyzw.xyz * r1_xyzw.xyz + r0_yzw;
  r2_xyzw.w = 1;
  float3 r3;
  r3.x = dot(r2_xyzw, m44_PreTonemapGlareColorTransformMatrix[0].xyzw);
  r3.y = dot(r2_xyzw, m44_PreTonemapGlareColorTransformMatrix[1].xyzw);
  r3.z = dot(r2_xyzw, m44_PreTonemapGlareColorTransformMatrix[2].xyzw);
  r2_xyzw = atex2D_Texture[0].Sample(asamp2D_Texture[0], TEXCOORD0);
  r1_xyzw.xyz = r1_xyzw.xyz * r2_xyzw.xyz;
  output.SV_TARGET.w = dot(r2_xyzw, afRGBA_Modulate[1].xyzw);
  r1_xyzw.w = 1;
  r2_xyzw.x = dot(r1_xyzw, m44_PreTonemapColorTransformMatrix[0].xyzw);
  r2_xyzw.y = dot(r1_xyzw, m44_PreTonemapColorTransformMatrix[1].xyzw);
  r2_xyzw.z = dot(r1_xyzw, m44_PreTonemapColorTransformMatrix[2].xyzw);
  float3 r0_xyz = r2_xyzw.xyz * r0x + r3;
  #ifdef __CSP_PROVIDE_TEXCOORDS
    r0_xyz = main(max(0, r0_xyz), TEXCOORD0);
  #else
    r0_xyz = main(max(0, r0_xyz));
  #endif
  r0_xyz = saturate(r0_xyz + 0.0000000001);
  r0_xyz = pow(r0_xyz, fParam_GammaCorrection.x); 
  r1_xyzw = atex2D_Texture[3].Sample(asamp2D_Texture[3], TEXCOORD4);
  r0_xyz = r1_xyzw.x * fParam_DitherOffsetScale.x + r0_xyz;
  output.SV_TARGET.xyz = r0_xyz + fParam_DitherOffsetScale.y;
  return output;
}
