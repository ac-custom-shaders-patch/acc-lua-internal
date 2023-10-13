namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public static class GainEstimator {
        public static UserTransformState Own;

        public static void Update(MuVec3 pos, ref float gainLeft, ref float gainRight, ref float offsetLeft, ref float offsetRight) {
            var own = Own;
            if (own == null) return;
            own.Estimate3dGainFor(pos, ref gainLeft, ref gainRight, ref offsetLeft, ref offsetRight);
        }
    }
}