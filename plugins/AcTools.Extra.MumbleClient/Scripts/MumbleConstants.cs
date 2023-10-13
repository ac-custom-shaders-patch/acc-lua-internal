namespace Mumble {
    public static class MumbleConstants {
        public const int MAX_SAMPLE_RATE = 48000;

        public static readonly int[] SUPPORTED_SAMPLE_RATES = {
            8000,
            12000,
            16000,
            24000,
            48000
        };

        public const int OUTPUT_FRAME_SIZE = MAX_SAMPLE_RATE / 100;
        public const int PING_INTERVAL_MS = 1000;
        public const int MAX_FRAMES_PER_PACKET = 6;
        public const int NUM_FRAMES_PER_OUTGOING_PACKET = 2;
        public const int FRAME_SIZE_MS = NUM_FRAMES_PER_OUTGOING_PACKET * 10;
        public const int MAX_CHANNELS = 2;
        public const int MAX_CONSECUTIVE_MISSED_UDP_PINGS = 5;
    }
}