float GetCloudShadow(){
  return getCloudShadow(PosC);
}

float GetEmissiveMult(){
  return gEmissiveMults.x;
}

float GetDithering(){  // add this value to output sky color or something like that to avoid banding
  float m = lerp(0.00196, -0.00196, frac(0.25 + dot(PosH.xy, 0.5)));
  #if USE_LINEAR_COLOR_SPACE
    m *= gMainBrightnessMult;
  #endif
  return m;
}

float GetDepth(){
  return txDepth.SampleLevel(samLinearSimple, ScreenPos, 0);
}

float3 GetPosW(){
  return PosC + gCameraPosition;
}

float3 GetFogColor(){
  float3 fromCamera = normalize(PosC);
  float sunAmount = saturate(dot(-fromCamera, gLightDirection));
  #if USE_LINEAR_COLOR_SPACE
    float3 fogColor = gFogColor;

    float4 fog2Color_blend = __loadVector(p_fog2Color_blend);
    float yK = fromCamera.y / (gFogConstantPiece + sign(gFogConstantPiece) * abs(fromCamera.y));
    float buggyPart = 1 - exp(-max(length(PosC) - 2.4, 0) * pow(2, yK * 5) * p_fog2Linear); 
    float fog2 = fog2Color_blend.w * pow(saturate(buggyPart), p_fog2Exp);
    fogColor = lerp(fogColor, fog2Color_blend.rgb, saturate(fog2));

    fogColor += gLightColor.xyz * pow(sunAmount, gFogBacklitExp) * gFogBacklitMult;
    return fogColor;
  #else
    return gFogColor + gLightColor.xyz * pow(sunAmount, gFogBacklitExp) * gFogBacklitMult;
  #endif
}

float3 ApplyFog(float color, float fogMult = 1){
  return ApplyFog(color.xxx, fogMult);
}

float4 ApplyFog(float4 color, float fogMult = 1){
  return float4(ApplyFog(color.rgb, fogMult), color.a);
}

float GetFogMultiplier(float zenith, float horizon, float exp, float rangeMult){
  // gives multiplier the same way functions like ac.setSkyFogMultiplier() and ac.setHorizonFogMultiplier() work
  float3 fromCamera = normalize(PosC);
  float rangeInv = 1 / max(rangeMult, 0.01);
  return zenith + (horizon - zenith) * pow(saturate(rangeInv - fromCamera.y * rangeInv), exp);
}