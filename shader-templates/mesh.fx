/* Template for Lua shaders used by `render.mesh()` function */

$DEFINES~
$TEXTURES~
$INCLUDE_TEXTURES~
$INCLUDE_GENERIC~
$INCLUDE_SCENE~

cbuffer cbData : register(b10) { 
  $VALUES~
}

struct PS_IN { 
  float4 PosH : SV_POSITION; 
  float2 Tex : TEXCOORD0; 
  float2 ScreenPos : TEXCOORD1;  // screen pos from 0 to 1 to sample depth map with
  float3 PosC : TEXCOORD2;       // position of given pixel (at far clipping plane) in world coordinates relative to camera
  float Fog : TEXCOORD3;
  float3 PosL : TEXCOORD4;       // local mesh position
  float3 NormalW : TEXCOORD5;    // world-space normal

  $INCLUDE_PIN_METHODS~
  $INCLUDE_PIN_METHODS_GEOMETRY~
};

$CODE~
$INCLUDE_ENTRY~
