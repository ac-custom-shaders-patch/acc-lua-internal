using System;

namespace UnityEngine {
    public class RequireComponentAttribute : Attribute {
        public RequireComponentAttribute(Type type) { }
    }
}