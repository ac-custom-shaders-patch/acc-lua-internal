using System;

namespace UnityEngine {
    public static class Debug {
        public static void Log(string msg) {
            Console.Out.WriteLine("i: " + msg);
            Console.Out.Flush();
        }
        
        public static void LogWarning(string msg) {
            Console.Out.WriteLine("W: " + msg);
            Console.Out.Flush();
        }

        public static void LogError(string msg) {
            Console.Out.WriteLine("E: " + msg);
            Console.Out.Flush();
        }

        public static void LogResponse(string msg) {
            Console.Out.WriteLine("!: " + msg);
            Console.Out.Flush();
        }
    }
}