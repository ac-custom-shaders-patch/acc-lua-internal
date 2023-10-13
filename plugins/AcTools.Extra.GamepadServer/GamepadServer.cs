using System;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Fleck;
using QRCoder;

namespace AcTools.Extra.GamepadServer {
    public class GamepadServer : IDisposable {
        private readonly WebSocketServer _wsServer;
        // private UdpSocketServer _udpServer;
        // private string _clientIpAddress;
        private readonly GamepadProvider _provider;
        private readonly GamepadInterpolator _interpolator = new GamepadInterpolator();
        private IWebSocketConnection _wsClient;
        private GamepadState _state;
        private GamepadOutputState _outputState;
        private int _connected;
        private bool _running = true;

        public GamepadServer(int port) {
            _provider = new GamepadProvider();
            _provider.Open();

            _wsServer = new WebSocketServer(IPAddress.Any, port);
            _wsServer.Start(socket => {
                socket.OnOpen = () => {
                    Console.WriteLine("New connection (total connections: " + ++_connected + ")");
                    _state = new GamepadState();
                    _outputState = new GamepadOutputState();

                    if (_wsClient?.IsAvailable == true) {
                        _wsClient.Close();
                    }
                    _wsClient = socket;
                    
                    /*_udpServer?.Dispose();
                    _udpServer = null;
                    _clientIpAddress = socket.ConnectionInfo.ClientIpAddress;*/

                    var msg = $"P{_interpolator.GetCurrentTime()}";
                    _provider.Read(ref msg, ref _outputState, true);
                    _wsClient?.Send(msg);

                    _state.Steer = _interpolator.GetCurrentTime();
                    _state.PacketTime = _interpolator.GetCurrentTime() - 1;
                    _state.CurrentTime = _interpolator.GetCurrentTime();
                    _provider.Write(ref _state);
                };
                socket.OnClose = () => {
                    if (_wsClient == socket) {
                        _wsClient = null;
                        //_udpServer?.Dispose();
                        //_udpServer = null;
                    }
                    Console.WriteLine("Connection closed (total connections: " + --_connected + ")");
                };
                socket.OnError = e => {
                    if (_wsClient == socket) {
                        _wsClient = null;
                        //_udpServer?.Dispose();
                        //_udpServer = null;
                    }
                    Console.WriteLine("Connection error: " + e);
                };
                socket.OnMessage = ProcessIncomingData;
            });
            
            /*_udpServer = new UdpSocketServer(port + 1);
            new Thread(() => {
                int i = 0;
                while (true) {
                    _udpServer.Send("Test: " + ++i);
                    Thread.Sleep(1000);
                }
            }).Start();*/

            var serverUrl = $"ws://{GetLanIp()}:{port}";
            var qrGenerator = new QRCodeGenerator();
            var qrCodeData = qrGenerator.CreateQrCode(serverUrl, QRCodeGenerator.ECCLevel.Q);
            var qrFilename = Environment.GetEnvironmentVariable("GAMEPAD_SERVER_IMAGE") ?? "qr.png";
            if (File.Exists(qrFilename)) File.Delete(qrFilename);
            new QRCode(qrCodeData).GetGraphic(40).Save(qrFilename, ImageFormat.Png);
            Console.WriteLine($"Server URL: {serverUrl}");
            Console.WriteLine($"QR filename: {qrFilename}");

            new Thread(() => {
                while (_running) {
                    _provider.WriteTime(_interpolator.GetCurrentTime());
                    Thread.Sleep(1);
                }
            }).Start();
        }

        private static string GetLanIp() {
            foreach (var address in Dns.GetHostEntry(Dns.GetHostName()).AddressList
                    .Where(x => x.AddressFamily == AddressFamily.InterNetwork)) {
                Console.WriteLine($"LAN IP candidate: {address}");
            }
            return Dns.GetHostEntry(Dns.GetHostName()).AddressList
                    .FirstOrDefault(x => x.AddressFamily == AddressFamily.InterNetwork)?.ToString()
                    ?? throw new Exception("Failed to find LAN IP");
        }

        /*private void UpgradeToUdp(string param) {
            Console.WriteLine("Upgrading to UDP: " + param + " (client: " + _clientIpAddress + ")");
            _udpServer = new UdpSocketServer(_clientIpAddress, int.Parse(param));
            new Thread(() => {
                int i = 0;
                while (true) {
                    _udpServer.Send("Test: " + ++i);
                    Thread.Sleep(1000);
                }
            }).Start();
        }*/

        private void ProcessIncomingData(string data) {
            try {
                if (data.Length > 2 && data[0] == 'U') {
                   // UpgradeToUdp(data.Substring(1));
                    return;
                }
                
                if (_state.Parse(data, _interpolator)) {
                    _state.PacketTime = _interpolator.GetCurrentTime() - _interpolator.GetPingMs();
                }

                _state.CurrentTime = _interpolator.GetCurrentTime();
                _provider.Write(ref _state);

                var msg = $"P{_interpolator.GetCurrentTime()}";
                _provider.Read(ref msg, ref _outputState, false);
                _wsClient?.Send(msg);
            } catch (Exception e) {
                Console.Error.WriteLine(e);
                Console.Error.WriteLine("Data: " + data);
            }
        }

        public void Dispose() {
            _wsServer?.Dispose();
            _provider?.Dispose();
            _wsClient = null;
            _running = false;
        }
    }
}