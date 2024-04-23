SamplerState samLinear : register(s0) { Filter = LINEAR; AddressU = WRAP; AddressV = WRAP;};
SamplerComparisonState samShadow : register(s1) { Filter = COMPARISON_MIN_MAG_MIP_LINEAR; AddressU = BORDER; AddressV = BORDER; AddressW = BORDER; BorderColor = 1; ComparisonFunc = LESS;};
SamplerState samPoint : register(s2) { Filter = POINT; AddressU = WRAP; AddressV = WRAP;};
SamplerState samLinearSimple : register(s5) { Filter = LINEAR; AddressU = WRAP; AddressV = WRAP;};
SamplerState samLinearBorder0 : register(s6) { Filter = MIN_MAG_MIP_LINEAR; AddressU = BORDER; AddressV = BORDER; AddressW = BORDER; BorderColor = (float4)0;};
SamplerState samLinearBorder1 : register(s7) { Filter = MIN_MAG_MIP_LINEAR; AddressU = Border; AddressV = Border; AddressW = Border; BorderColor = (float4)1;};
SamplerState samLinearClamp : register(s8) { Filter = MIN_MAG_MIP_LINEAR; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP;};
SamplerState samPointClamp : register(s9) { Filter = POINT; AddressU = CLAMP; AddressV = CLAMP;};
SamplerState samPointBorder0 : register(s10) { Filter = POINT; AddressU = CLAMP; AddressV = CLAMP;};
SamplerState samAnisotropic : register(s11) { Filter = LINEAR; AddressU = WRAP; AddressV = WRAP;};
SamplerState samAnisotropicClamp : register(s12) { Filter = LINEAR; AddressU = CLAMP; AddressV = CLAMP;};

#ifdef __USE_GAMMA_FIX
  #define USE_LINEAR_COLOR_SPACE 1
#else
  #define USE_LINEAR_COLOR_SPACE 0
#endif
