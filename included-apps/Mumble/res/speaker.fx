float sdArc2(float2 p, float2 coords, float a0, float a1, float r) {
  p -= coords;
  float a = fmod(atan2(p.y, p.x), radians(360.));
  float ap = a - a0;
  if (ap < 0.) ap += radians(360.);
  float a1p = a1 - a0;
  if (a1p < 0.) a1p += radians(360.);
  if (ap >= a1p) {
    float2 q0 = float2(r * cos(a0), r * sin(a0));
    float2 q1 = float2(r * cos(a1), r * sin(a1));
    return min(length(p - q0), length(p - q1));
  }
  return abs(length(p) - r);
}

float4 main(PS_IN pin) { 
  if (pin.Tex.x > 0.6){
    float r0, r;

    {
      float m0 = 1, m1 = 1, m2 = 1;
      r0 = sdArc2(pin.Tex, float2(0.2, 0.5), -0.3 * m0, 0.3 * m0, 0.5) + 0.04 * (1 - saturate(m0 * 40));
      r0 = min(r0, sdArc2(pin.Tex, float2(0.2, 0.5), -0.4 * m1, 0.4 * m1, 0.625) + 0.04 * (1 - saturate(m1 * 40)));
      r0 = min(r0, sdArc2(pin.Tex, float2(0.2, 0.5), -0.5 * m2, 0.5 * m2, 0.75) + 0.04 * (1 - saturate(m2 * 40)));
    }

    {
      float m0 = saturate(gPos * 3);
      float m1 = saturate(gPos * 3 - 1);
      float m2 = saturate(gPos * 3 - 2);
      r = sdArc2(pin.Tex, float2(0.2, 0.5), -0.3 * m0, 0.3 * m0, 0.5) + 0.05 * (1 - saturate(m0 * 40));
      r = min(r, sdArc2(pin.Tex, float2(0.2, 0.5), -0.4 * m1, 0.4 * m1, 0.625) + 0.05 * (1 - saturate(m1 * 40)));
      r = min(r, sdArc2(pin.Tex, float2(0.2, 0.5), -0.5 * m2, 0.5 * m2, 0.75) + 0.05 * (1 - saturate(m2 * 40)));
    }

    float a = lerp(0.3, 1, saturate((0.05 - r) * 400));
    return float4(a, a, a, saturate((0.05 - r0) * 40));
  } else {
    return txIcon.Sample(samLinear, pin.Tex);
  }
}
