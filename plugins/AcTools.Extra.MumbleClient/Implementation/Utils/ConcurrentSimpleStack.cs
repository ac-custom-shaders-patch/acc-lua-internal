using System.Threading;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class ConcurrentSimpleStack<T> {
        private class Node {
            public Node Next;
            public T Item;
        }

        private readonly Node _head = new Node();

        public void Push(T item) {
            var node = new Node { Item = item };
            do {
                node.Next = _head.Next;
            } while (!CompareAndSwap(ref _head.Next, node.Next, node));
        }

        public bool Pop(out T result) {
            Node node;
            do {
                node = _head.Next;
                if (node == null) {
                    result = default;
                    return false;
                }
            } while (!CompareAndSwap(ref _head.Next, node, node.Next));
            result = node.Item;
            return true;
        }

        public void Clear() {
            _head.Next = null;
        }

        private static bool CompareAndSwap(ref Node destination, Node currentValue, Node newValue) {
            return currentValue == Interlocked.CompareExchange(ref destination, newValue, currentValue);
        }
    }
}