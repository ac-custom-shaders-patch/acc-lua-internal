using System.Collections.Generic;
using UnityEngine;
using System;
using System.Collections.Concurrent;
using System.Threading;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Debug = UnityEngine.Debug;

namespace Mumble {
    public class AudioDecodeThread : IDisposable {
        private readonly AutoResetEvent _waitHandle;
        private readonly Queue<OpusDecoder> _unusedDecoders = new Queue<OpusDecoder>();
        private readonly Dictionary<uint, DecoderState> _currentDecoders = new Dictionary<uint, DecoderState>();
        private readonly ConcurrentQueue<MessageData> _messageQueue = new ConcurrentQueue<MessageData>();

        private bool _disposed;

        /// <summary>
        /// How many packets go missing before we figure they were lost
        /// Due to murmur
        /// </summary>
        private const long MaxMissingPackets = 25;

        private const int SubBufferSize = MumbleConstants.OUTPUT_FRAME_SIZE * MumbleConstants.MAX_FRAMES_PER_PACKET * MumbleConstants.MAX_CHANNELS;

        public AudioDecodeThread() {
            _waitHandle = new AutoResetEvent(false);
            new Thread(DecodeThread).Start();
        }

        internal void StartDecoding(AudioSource source) {
            _messageQueue.Enqueue(new MessageData { Audio = source });
        }

        internal void StopDecoding(uint session) {
            _messageQueue.Enqueue(new MessageData { Session = session });
        }

        internal void AddCompressedAudio(uint session, byte[] audioData, int audioSize, MuVec3 posData, long sequence, bool isLast) {
            if (_disposed) {
                UdpPacketReader.ReleaseOpusVoiceData(ref audioData);
                return;
            }

            _messageQueue.Enqueue(new MessageData {
                Session = session,
                CompressedAudio = audioData,
                CompressedLength = audioSize,
                PosData = posData,
                Sequence = sequence,
                IsLast = isLast
            });
            _waitHandle.Set();
        }

        private void DecodeThread() {
            while (!_disposed) {
                _waitHandle.WaitOne();
                while (!_disposed) {
                    try {
                        if (!_messageQueue.TryDequeue(out var messageData)) break;

                        if (messageData.CompressedAudio != null) {
                            if (_currentDecoders.TryGetValue(messageData.Session, out var decoderState)) {
                                DecodeAudio(messageData.Session, decoderState, messageData.CompressedAudio, messageData.CompressedLength,
                                        messageData.PosData, messageData.Sequence, messageData.IsLast);
                            } else {
                                UdpPacketReader.ReleaseOpusVoiceData(ref messageData.CompressedAudio);
                            }
                        } else if (messageData.Audio != null) {
                            _currentDecoders[messageData.Audio._user.Session] = new DecoderState { Audio = messageData.Audio };
                        } else if (_currentDecoders.TryGetValue(messageData.Session, out var decoderState)) {
                            _currentDecoders.Remove(messageData.Session);
                            if (decoderState.Decoder != null) {
                                _unusedDecoders.Enqueue(decoderState.Decoder);
                            }
                        }
                    } catch (Exception e) {
                        Debug.LogError("Exception in decode thread: " + e);
                    }
                }
            }
        }

        private static readonly float[] PcmBuffer = new float[SubBufferSize];

        private void DecodeAudio(uint session, DecoderState decoderState, byte[] compressedAudio, int compressedLength, MuVec3 posData, long sequence, bool isLast) {
            var player = decoderState.Audio;
            if (!player.ReadyToReceive()) {
                if (decoderState.Decoder != null) {
                    decoderState.WasPrevPacketMarkedLast = true;
                    decoderState.NextSequenceToDecode = 0;
                    _unusedDecoders.Enqueue(decoderState.Decoder);
                    decoderState.Decoder = null;
                }
                UdpPacketReader.ReleaseOpusVoiceData(ref compressedAudio);
                return;
            }

            if (decoderState.Decoder == null) {
                if (_unusedDecoders.Count > 0) {
                    decoderState.Decoder = _unusedDecoders.Dequeue();
                    decoderState.Decoder.ResetState();
                } else {
                    decoderState.Decoder = new OpusDecoder(AudioSettings.outputSampleRate, (int)AudioSettings.speakerMode);
                }
            }

            // We tell the decoded buffer to re-evaluate whether it needs to store a few packets if the previous packet was marked last, or if there
            // was an abrupt change in sequence number
            var reevaluateInitialBuffer = decoderState.WasPrevPacketMarkedLast;

            // Account for missing packets, out-of-order packets, & abrupt sequence changes
            if (decoderState.NextSequenceToDecode != 0) {
                var seqDiff = sequence - decoderState.NextSequenceToDecode;

                // If new packet is VERY late, then the sequence number has probably reset
                if (seqDiff < -MaxMissingPackets) {
                    Debug.Log("Sequence has possibly reset diff = " + seqDiff);
                    decoderState.Decoder.ResetState();
                    reevaluateInitialBuffer = true;
                }
                // If the packet came before we were expecting it to, but after the last packet, the sampling has probably changed
                // unless the packet is a last packet (in which case the sequence may have only increased by 1)
                else if (sequence > decoderState.LastReceivedSequence && seqDiff < 0 && !isLast) {
                    Debug.Log("Mumble sample rate may have changed");
                }
                // If the sequence number changes abruptly (which happens with push to talk)
                else if (seqDiff > MaxMissingPackets) {
                    Debug.Log("Mumble packet sequence changed abruptly pkt: " + sequence + " last: " + decoderState.LastReceivedSequence);
                    reevaluateInitialBuffer = true;
                }
                // If the packet is a bit late, drop it
                else if (seqDiff < 0 && !isLast) {
                    Debug.LogWarning("Received old packet " + sequence + " expecting " + decoderState.NextSequenceToDecode);
                    UdpPacketReader.ReleaseOpusVoiceData(ref compressedAudio);
                    return;
                }
                // If we missed a packet, add a null packet to tell the decoder what happened
                else if (seqDiff > 0) {
                    Debug.LogWarning("Dropped packet: received: " + sequence + ", expected " + decoderState.NextSequenceToDecode);
                    /*var emptySampleNumRead = decoderState.Decoder.Decode(null, 0, PcmBuffer);
                    decoderState.NextSequenceToDecode = sequence
                            + emptySampleNumRead / ((AudioSettings.outputSampleRate / 100) * (int)AudioSettings.speakerMode);*/
                    var fecSamplesRead = decoderState.Decoder.Decode(compressedAudio, compressedLength, PcmBuffer, true);
                    decoderState.NextSequenceToDecode = sequence
                            + fecSamplesRead / ((AudioSettings.outputSampleRate / 100) * (int)AudioSettings.speakerMode);

                    // Send this decoded data to the corresponding buffer
                    // player.ReceiveDecodedVoice(PcmBuffer, emptySampleNumRead, posData, reevaluateInitialBuffer, true);
                    player.ReceiveDecodedVoice(PcmBuffer, fecSamplesRead, posData, reevaluateInitialBuffer, false);
                    reevaluateInitialBuffer = false;
                }
            }

            var numRead = 0;
            if (compressedLength != 0) {
                numRead = decoderState.Decoder.Decode(compressedAudio, compressedLength, PcmBuffer, false);
                player.ReceiveDecodedVoice(PcmBuffer, numRead, posData, reevaluateInitialBuffer, isLast);
                UdpPacketReader.ReleaseOpusVoiceData(ref compressedAudio);
            } else if (compressedAudio.Length > 0) {
                Debug.LogError("Unexpected state failure");
                UdpPacketReader.ReleaseOpusVoiceData(ref compressedAudio);
            }

            if (numRead < 0) {
                Debug.LogError("num read is < 0");
                return;
            }

            decoderState.WasPrevPacketMarkedLast = isLast;
            decoderState.LastReceivedSequence = sequence;
            if (isLast) {
                Debug.Log("Resetting #" + session + " decoder, numRead=" + numRead);
                decoderState.NextSequenceToDecode = 0;
                decoderState.Decoder.ResetState();
                if (compressedLength == 0) {
                    player.ReceiveDecodedVoice(null, numRead, posData, false, true);
                }
            } else {
                decoderState.NextSequenceToDecode = sequence + numRead / (AudioSettings.outputSampleRate / 100 * (int)AudioSettings.speakerMode);
            }
        }

        public void Dispose() {
            if (_disposed) return;
            _disposed = true;
        }

        private class MessageData {
            public byte[] CompressedAudio;
            public int CompressedLength;
            public AudioSource Audio;
            public MuVec3 PosData;
            public long Sequence;
            public uint Session;
            public bool IsLast;
        }

        private class DecoderState {
            public AudioSource Audio;
            public OpusDecoder Decoder;
            public long NextSequenceToDecode;
            public long LastReceivedSequence;
            public bool WasPrevPacketMarkedLast;
        }
    }
}