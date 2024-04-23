#define TX_SLOT(X) t##X
#define TX_SLOT_REFLECTION_CUBEMAP TX_SLOT(13)  
#define TX_SLOT_SHADOW_ARRAY TX_SLOT(14)
#define TX_SLOT_SHADOW_CLOUDS TX_SLOT(15)
#define TX_SLOT_DYNAMIC_SHADOWS TX_SLOT(16)
#define TX_SLOT_AO TX_SLOT(17)
#define TX_SLOT_DEPTH TX_SLOT(18)
#define TX_SLOT_PREV_FRAME TX_SLOT(19)
#define TX_SLOT_NOISE TX_SLOT(20)
#define TX_SLOT_BDRF TX_SLOT(21)
#define TX_SLOT_SHADOW_COLOR TX_SLOT(22)
#define TX_SLOT_MIRAGE_MASK TX_SLOT(23)

// 32×32 noise texture:
Texture2D txNoise : register(TX_SLOT_NOISE);

// These textures are only available in main pass:
Texture2D<float> txDepth : register(TX_SLOT_DEPTH);
Texture2D txPreviousFrame : register(TX_SLOT_PREV_FRAME);
TextureCube txReflectionCubemap : register(TX_SLOT_REFLECTION_CUBEMAP);
Texture2D<float> txCloudShadow__ : register(TX_SLOT_SHADOW_CLOUDS);