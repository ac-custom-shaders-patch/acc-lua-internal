float4 __fixType(float v){ return v; }
float4 __fixType(float2 v){ return float4(v, 0, 0); }
float4 __fixType(float3 v){ return float4(v, 0); }
float4 __fixType(float4 v){ return v; }

float4 entryPoint(PS_IN pin) : SV_TARGET { 
  #ifdef __CSP_APPLY_REGION_CLIP
    pin.RegionClip();
  #endif
  return __fixType(main(pin));
}
