/* Template for Lua shaders used by `ui.renderShader()` function */

$DEFINES~
$TEXTURES~
$INCLUDE_GENERIC~
#ifdef __CSP_SCENE_DATA
$INCLUDE_SCENE~
#endif

cbuffer cbDataRegionClip : register(b11) { 
  float2 gFrom; 
  float2 gTo; 
}

cbuffer cbData : register(b10) { 
  $VALUES~
}

#define __CSP_APPLY_REGION_CLIP

struct PS_IN { 
  float4 PosH : SV_POSITION; 
  noperspective float2 Tex : TEXCOORD0; 

  void RegionClip() {
    if (any(PosH.xy < gFrom || PosH.xy > gTo)) discard;
  }

  float GetDithering(){  // add this value to output sky color or something like that to avoid banding
    return lerp(0.00196, -0.00196, frac(0.25 + dot(PosH.xy, 0.5)));
  }
};

$CODE~
$INCLUDE_ENTRY~