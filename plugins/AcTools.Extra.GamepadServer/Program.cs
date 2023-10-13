using System;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using QRCoder;

namespace AcTools.Extra.GamepadServer {
    internal class Program {
        public static int Main(string[] args) {
            try {
                var messageToEncode = Environment.GetEnvironmentVariable("GAMEPAD_QR_DATA");
                if (messageToEncode != null) {
                    var qrGenerator = new QRCodeGenerator();
                    var qrCodeData = qrGenerator.CreateQrCode(messageToEncode, QRCodeGenerator.ECCLevel.Q);
                    var qrFilename = Environment.GetEnvironmentVariable("GAMEPAD_QR_FILENAME") ?? "qr.png";
                    if (File.Exists(qrFilename)) File.Delete(qrFilename);
                    new QRCode(qrCodeData).GetGraphic(40).Save(qrFilename, ImageFormat.Png);
                    return 0;
                }
                
                var port = int.Parse(Environment.GetEnvironmentVariable("GAMEPAD_SERVER_PORT") ?? "14014",
                        NumberStyles.Any, CultureInfo.InvariantCulture);
                var server = new GamepadServer(port);
                Console.WriteLine($"Server is running, port: {port}");
                Console.ReadLine();
                server.Dispose();
                return 0;
            } catch (Exception e) {
                Console.Error.WriteLine(e.ToString());
                return 1;
            }
        }
    }
}