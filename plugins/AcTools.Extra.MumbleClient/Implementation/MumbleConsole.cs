// Requires some extensions of default Mumble-Unity implementation to exchange plugin context and such
#define USE_POSITIONAL_ADJUSTMENT

using System;
using System.Linq;
using System.Text;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Mumble;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation {
    /// <summary>
    /// Testing version of Mumble client meant to run from console.
    /// </summary>
    public class MumbleConsole : IDisposable {
        private MonoBehaviour.IMonoRunner _runner;
        private Mumble.MumbleClient _mumbleClient;

        private MumbleMicrophone MyMumbleMic;

        public bool SendPosition = true;
        public bool ProcessPosition = true;
        public string HostName = "127.0.0.1";
        public int Port = 64738;
        public string Username = "ExampleUser2";
        public string Password = "1passwordHere!";
        public string ChannelToJoin = "";

#if USE_POSITIONAL_ADJUSTMENT
        public string PluginAppName = "Assetto Corsa";
        public string PluginContext = "offline";
#endif

        private readonly UserTransformState _ownTransform = new UserTransformState();

        public MumbleConsole() {
            _runner = MonoBehaviour.CreateRunner(Update);
            MyMumbleMic = _runner.CreateMono<MumbleMicrophone>();
            MyMumbleMic.MicNumberToUse = 2;
        }

        public void Run() {
            _mumbleClient?.Close();

            var posLength = SendPosition ? MuVec3.Size : 0;
            _mumbleClient = new Mumble.MumbleClient(HostName, Port, CreateMumbleAudioPlayerFromPrefab,
                    DestroyMumbleAudioPlayer, OnOtherUserStateChange, false,
                    SpeakerCreationMode.IN_ROOM_NOT_SERVER_MUTED, posLength);

            _mumbleClient.Connect(Username, Password);
            if (MyMumbleMic != null) {
                _mumbleClient.AddMumbleMic(MyMumbleMic);
                if (SendPosition)
                    MyMumbleMic.SetPositionalDataFunction(WritePositionalData);
            }
            _runner.Start();
        }

        private MumbleAudioPlayer CreateMumbleAudioPlayerFromPrefab(string username, uint session) {
            var ret = _runner.CreateMono<MumbleAudioPlayer>();
#if USE_POSITIONAL_ADJUSTMENT
            if (ProcessPosition) {
                ret._AddLinked(new GainEstimator(_ownTransform));
            }
#endif
            return ret;
        }

        private void OnOtherUserStateChange(uint session, MumbleProto.UserState updatedDeltaState, MumbleProto.UserState fullUserState) {
            print("User #" + session + " had their user state change");
            // Here we can do stuff like update a UI with users' current channel/mute etc.
        }

        private void DestroyMumbleAudioPlayer(uint session, MumbleAudioPlayer playerToDestroy) {
            playerToDestroy.Destroy();
        }

        private void WritePositionalData(ref byte[] posData, out int posDataLength) {
            _ownTransform.Pos.Serialize(posData, 0);
            posDataLength = MuVec3.Size;
        }

        private void Update() {
            _ownTransform.Pos = new MuVec3();

            if (_mumbleClient == null || !_mumbleClient.ReadyToConnect)
                return;

            if (Input.GetKeyDown(KeyCode.S)) {
                _mumbleClient.SendTextMessage("This is an example message from Unity");
                print("Sent mumble message");
            }
            if (Input.GetKeyDown(KeyCode.J)) {
                print("Will attempt to join channel " + ChannelToJoin);
                _mumbleClient.JoinChannel(ChannelToJoin);
            }
            if (Input.GetKeyDown(KeyCode.Escape)) {
                print("Will join root");
                _mumbleClient.JoinChannel("Root");
            }
            if (Input.GetKeyDown(KeyCode.C)) {
                print("Will set our comment");
                _mumbleClient.SetOurComment("Example Comment");
            }
            if (Input.GetKeyDown(KeyCode.B)) {
                print("Will set our texture");
                byte[] commentHash = new byte[] { 1, 2, 3, 4, 5, 6 };
                _mumbleClient.SetOurTexture(commentHash);
            }
            
            if (Input.GetKeyDown(KeyCode.M)) {
                var cur = MyMumbleMic.GetCurrentMicName();
                var next = DevicesHolder.GetInDeviceNames().SkipWhile(x => x != cur).Skip(1).FirstOrDefault() 
                        ?? DevicesHolder.GetInDeviceNames().FirstOrDefault();
                print($"Change mic from {cur} to {next}");

                MyMumbleMic.MicNumberToUse = Array.IndexOf(Microphone.devices, next);
                _mumbleClient.AddMumbleMic(MyMumbleMic);
            }
            
            if (Input.GetKeyDown(KeyCode.P)) {
                /*var cur = DevicesHolder.GetOutDeviceNames()[DevicesHolder.GetOutDeviceIndex(SharedSettings.OutputDeviceName)];
                var next = DevicesHolder.GetOutDeviceNames().SkipWhile(x => x != cur).Skip(1).FirstOrDefault() 
                        ?? DevicesHolder.GetOutDeviceNames().FirstOrDefault();
                print($"Change speaker from {cur} to {next}");
                SharedSettings.Processor.Process($"audio.outputDevice\t{next}");*/
                
                _mumbleClient.SetLocalMute(13, !_mumbleClient.IsUserIDLocalMuted(13));
            }

#if USE_POSITIONAL_ADJUSTMENT
            if (Input.GetKeyDown(KeyCode.X)) {
                print("Will set context");
                // Matches Link format (for testing)
                byte[] commentHash = Encoding.ASCII.GetBytes(PluginAppName).Concat(new byte[] { 0 }).Concat(Encoding.ASCII.GetBytes(PluginContext)).ToArray();
                _mumbleClient.SetPluginContext(commentHash);
            }

            if (Input.GetKeyDown(KeyCode.W)) {
                print("Will set plugin identity to TEST");
                _mumbleClient.SetPluginIdentity("TEST");
            }

            if (Input.GetKeyDown(KeyCode.E)) {
                print("Will set plugin identity to TEST2");
                _mumbleClient.SetPluginIdentity("TEST2");
            }
#endif

            // You can buse the up / down arrows to increase/decrease
            // the bandwidth used by the mumble mic
            const int BandwidthChange = 5000;
            if (Input.GetKeyDown(KeyCode.UpArrow)) {
                int currentBW = MyMumbleMic.GetBitrate();
                int newBitrate = currentBW + BandwidthChange;
                Debug.Log("Increasing bitrate " + currentBW + "->" + newBitrate);
                MyMumbleMic.SetBitrate(newBitrate);
            }
            if (Input.GetKeyDown(KeyCode.DownArrow)) {
                int currentBW = MyMumbleMic.GetBitrate();
                int newBitrate = currentBW - BandwidthChange;
                Debug.Log("Decreasing bitrate " + currentBW + "->" + newBitrate);
                MyMumbleMic.SetBitrate(newBitrate);
            }
        }

        private void print(string msg) {
            Debug.Log(msg);
        }

        public void Dispose() {
            _mumbleClient?.Close();
        }
    }
}