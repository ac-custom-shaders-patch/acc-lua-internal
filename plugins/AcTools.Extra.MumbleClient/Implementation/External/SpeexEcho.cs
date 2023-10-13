using System;
using System.Runtime.InteropServices;

namespace AcTools.Extra.MumbleClient.Implementation.External {
    public static class SpeexEcho {
        // define library path
        private const string DLLPath = "libspeexdsp.dll";

        /** Obtain frame size used by the AEC */
        public static int SPEEX_ECHO_GET_FRAME_SIZE = 3;

        /** Set sampling rate */
        public static int SPEEX_ECHO_SET_SAMPLING_RATE = 24;

        /** Get sampling rate */
        public static int SPEEX_ECHO_GET_SAMPLING_RATE = 25;

        /* Can't set window sizes */

        /** Get size of impulse response (int32) */
        public static int SPEEX_ECHO_GET_IMPULSE_RESPONSE_SIZE = 27;

        /** Get impulse response (int32[]) */
        public static int SPEEX_ECHO_GET_IMPULSE_RESPONSE = 29;

        /** Creates a new echo canceller state
         * @param frame_size Number of samples to process at one time (should correspond to 10-20 ms)
         * @param filter_length Number of samples of echo to cancel (should generally correspond to 100-500 ms)
         * @return Newly-created echo canceller state
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr speex_echo_state_init(int frame_size, int filter_length);

        /** Creates a new multi-channel echo canceller state
         * @param frame_size Number of samples to process at one time (should correspond to 10-20 ms)
         * @param filter_length Number of samples of echo to cancel (should generally correspond to 100-500 ms)
         * @param nb_mic Number of microphone channels
         * @param nb_speakers Number of speaker channels
         * @return Newly-created echo canceller state
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr speex_echo_state_init_mc(int frame_size, int filter_length, int nb_mic, int nb_speakers);

        /** Destroys an echo canceller state
         * @param st Echo canceller state
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_echo_state_destroy(IntPtr st);

        /** Performs echo cancellation a frame, based on the audio sent to the speaker (no delay is added
         * to playback in this form)
         *
         * @param st Echo canceller state
         * @param rec Signal from the microphone (near end + far end echo)
         * @param play Signal played to the speaker (received from far end)
         * @param outt Returns near-end signal with echo removed
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_echo_cancellation(IntPtr st, short[] rec, short[] play, short[] outt);

        // byte array version, as long as audio data is from 16 bit stream
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern unsafe void speex_echo_cancellation(IntPtr st, byte[] rec, byte[] play, byte* outt);

        /** Perform echo cancellation using internal playback buffer, which is delayed by two frames
         * to account for the delay introduced by most soundcards (but it could be off!)
         * @param st Echo canceller state
         * @param rec Signal from the microphone (near end + far end echo)
         * @param outt Returns near-end signal with echo removed
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_echo_capture(IntPtr st, short[] rec, short[] outt);

        /** Let the echo canceller know that a frame was just queued to the soundcard
         * @param st Echo canceller state
         * @param play Signal played to the speaker (received from far end)
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_echo_playback(IntPtr st, short[] play);

        /** Reset the echo canceller to its original state
         * @param st Echo canceller state
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_echo_state_reset(IntPtr st);

        /** Used like the ioctl function to control the echo canceller parameters
         *
         * @param st Echo canceller state
         * @param request ioctl-type request (one of the SPEEX_ECHO_* macros)
         * @param ptr Data exchanged to-from function
         * @return 0 if no error, -1 if request in unknown
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern int speex_echo_ctl(IntPtr st, int request, IntPtr ptr);

        /** Create a state for the channel decorrelation algorithm
            This is useful for multi-channel echo cancellation only
         * @param rate Sampling rate
         * @param channels Number of channels (it's a bit pointless if you don't have at least 2)
         * @param frame_size Size of the frame to process at ones (counting samples *per* channel)
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr speex_decorrelate_new(int rate, int channels, int frame_size);

        /** Remove correlation between the channels by modifying the phase and possibly
            adding noise in a way that is not (or little) perceptible.
         * @param st Decorrelator state
         * @param inn Input audio in interleaved format
         * @param outt Result of the decorrelation (out *may* alias in)
         * @param strength How much alteration of the audio to apply from 0 to 100.
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_decorrelate(IntPtr st, short[] inn, short[] outt, int strength);

        /** Destroy a Decorrelation state
         * @param st State to destroy
        */
        [DllImport(DLLPath, CallingConvention = CallingConvention.Cdecl)]
        public static extern void speex_decorrelate_destroy(IntPtr st);
    }
}