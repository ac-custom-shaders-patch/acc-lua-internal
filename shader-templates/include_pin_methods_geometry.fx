float CalculateFogValue(bool usePerPixelFog){
  #if USE_LINEAR_COLOR_SPACE
    float3 fromCamera = normalize(PosC);
    float fogRecompute = 1 - exp(-length(PosC) * gFogLinear);
    float fog = usePerPixelFog ? gFogBlend * pow(saturate(fogRecompute), gFogExp) : Fog;
    float4 fog2Color_blend = __loadVector(p_fog2Color_blend);
    float yK = fromCamera.y / (gFogConstantPiece + sign(gFogConstantPiece) * abs(fromCamera.y));
    float buggyPart = 1 - exp(-max(length(PosC) - 2.4, 0) * pow(2, yK * 5) * p_fog2Linear); 
    float fog2 = fog2Color_blend.w * pow(saturate(buggyPart), p_fog2Exp);
    return lerp(fog, 1, fog2);
  #else
    [branch]
    if (usePerPixelFog && gUseNewFog){
      float3 fromCamera = normalize(PosC);
      if (abs(fromCamera.y) < 0.001) fromCamera.y = 0.001;
      float basePart = (1 - exp(-length(PosC) * fromCamera.y / gFogLinear)) / fromCamera.y;
      return gFogBlend * pow(saturate(gFogConstantPiece * basePart), gFogExp);
    }
    return Fog;
  #endif
}

float3 ApplyFog(float3 color, float fogMult = 1, bool usePerPixelFog = false){
  #if USE_LINEAR_COLOR_SPACE
    float3 fromCamera = normalize(PosC);
    float fog = Fog;
    if (usePerPixelFog) {
      float fogRecompute = 1 - exp(-length(PosC) * gFogLinear);
      fog = gFogBlend * pow(saturate(fogRecompute), gFogExp);
    }
      
    float3 fogIntensity = saturate(fog * fogMult);
    fogIntensity.r = lerp(fogIntensity.r, pow(fogIntensity.r, 3), gFogAtmosphere);
    fogIntensity.g = lerp(fogIntensity.g, pow(fogIntensity.g, 2), gFogAtmosphere);

    float3 fogColor = gFogColor;
    float sunAmount = saturate(dot(-fromCamera, gLightDirection));
    fogColor += gLightColor.xyz * pow(sunAmount, gFogBacklitExp) * gFogBacklitMult;
    color = lerp(color, fogColor, fogIntensity);

    float4 fog2Color_blend = __loadVector(p_fog2Color_blend);
    fog2Color_blend.rgb += gLightColor.xyz * pow(sunAmount, gFogBacklitExp) * gFogBacklitMult;
    float yK = fromCamera.y / (gFogConstantPiece + sign(gFogConstantPiece) * abs(fromCamera.y));
    float buggyPart = 1 - exp(-max(length(PosC) - 2.4, 0) * pow(2, yK * 5) * p_fog2Linear); 
    float fog2 = fog2Color_blend.w * pow(saturate(buggyPart), p_fog2Exp);
    color = lerp(color, fog2Color_blend.rgb, saturate(fog2 * fogMult));
    return color;
  #else
    return lerp(color, GetFogColor(), saturate(fogMult * CalculateFogValue(usePerPixelFog)));
  #endif
}

float FogAlphaMultiplier(float alpha, float fogMult = 1, bool usePerPixelFog = false){
  // deprecated (wrong name)
  return saturate(1 - fogMult * CalculateFogValue(usePerPixelFog));
}

float GetFogAlphaMultiplier(float alpha, float fogMult = 1, bool usePerPixelFog = false){
  return saturate(1 - fogMult * CalculateFogValue(usePerPixelFog));
}