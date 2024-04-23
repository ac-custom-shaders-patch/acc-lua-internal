/* Template for Lua shaders used by `ui.ExtraCanvas:updateWithShader()` function */

$DEFINES~
$TEXTURES~
$INCLUDE_GENERIC~
#ifdef __CSP_SCENE_DATA
$INCLUDE_SCENE~
#endif

cbuffer cbData : register(b10) { 
  $VALUES~
}

struct PS_IN { 
  float4 PosH : SV_POSITION; 
  noperspective float2 Tex : TEXCOORD0; 

  float GetDithering(){  // add this value to output sky color or something like that to avoid banding
    return lerp(0.00196, -0.00196, frac(0.25 + dot(PosH.xy, 0.5)));
  }
};

$CODE~
$INCLUDE_ENTRY~
