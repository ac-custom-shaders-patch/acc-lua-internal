using System;
using System.Runtime.CompilerServices;
using System.Runtime.ExceptionServices;
using System.Security;
using System.Security.Permissions;
using System.Threading.Tasks;
using AcTools.Extra.MumbleClient.Implementation;
using AcTools.Extra.MumbleClient.Implementation.Utils;

namespace AcTools.Extra.MumbleClient {
    internal class Program {
        // public static int Main(string[] args) {
        public static int Main(/*string[] args*/) {
            Console.OutputEncoding = MarshalMatters.ExchangeEncoding;
            try {
                SetUnhandledExceptionHandler();
                DevicesHolder.GetIn(null);
                MumbleMapped mapped;
                {
                    /*var inputData = args.Contains("--test") ? File.ReadAllText("C:/temp/test.txt") : Console.In.ReadToEnd();
                    if (File.Exists("C:/temp/test.txt")) {
                        File.WriteAllText("C:/temp/test.txt", inputData);
                    }
                    mapped = new MumbleMapped(inputData, args.Contains("--test"));*/
                    
                    mapped = new MumbleMapped(Console.In.ReadToEnd(), false);
                }
                GC.Collect();
                mapped.Run();
                return ExitCode.Success;
            } catch (Exception e) {
                Console.WriteLine("Error: " + e);
                Console.Out.Flush();
                Console.Error.Flush();
                return ExitCode.Exception;
            }
        }

        [SecurityPermission(SecurityAction.Demand, Flags = SecurityPermissionFlag.ControlAppDomain)]
        private static void SetUnhandledExceptionHandler() {
            AppDomain.CurrentDomain.UnhandledException += UnhandledExceptionHandler;
            TaskScheduler.UnobservedTaskException += UnobservedTaskException;
        }

        [HandleProcessCorruptedStateExceptions, SecurityCritical]
        private static void UnobservedTaskException(object sender, UnobservedTaskExceptionEventArgs args) {
            Console.Error.WriteLine("Unhandled task exception: " + args.Exception);
            if (!args.Observed) {
                Environment.Exit(ExitCode.Exception);
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining), HandleProcessCorruptedStateExceptions, SecurityCritical]
        private static void UnhandledExceptionHandler(object sender, UnhandledExceptionEventArgs args) {
            Console.Error.WriteLine("Unhandled exception: " + args.ExceptionObject);
            if (args.IsTerminating) {
                Environment.Exit(ExitCode.Exception);
            }
        }
    }
}