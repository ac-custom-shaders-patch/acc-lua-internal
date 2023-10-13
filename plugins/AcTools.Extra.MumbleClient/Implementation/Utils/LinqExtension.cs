using System.Collections.Generic;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public static class LinqExtension {
        public static int AddSorted<T>(this IList<T> list, T value, IComparer<T> comparer = null) {
            if (comparer == null) comparer = Comparer<T>.Default;

            var end = list.Count - 1;

            // Array is empty or new item should go in the end
            if (end == -1 || comparer.Compare(value, list[end]) > 0) {
                list.Add(value);
                return end + 1;
            }

            // Simplest version for small arrays
            if (end < 20) {
                for (end--; end >= 0; end--) {
                    if (comparer.Compare(value, list[end]) >= 0) {
                        list.Insert(end + 1, value);
                        return end + 1;
                    }
                }

                list.Insert(0, value);
                return list.Count - 1;
            }

            // Sort of binary search
            var start = 0;
            while (true) {
                if (end == start) {
                    list.Insert(start, value);
                    return start;
                }

                if (end == start + 1) {
                    if (comparer.Compare(value, list[start]) <= 0) {
                        list.Insert(start, value);
                        return start;
                    }

                    list.Insert(end, value);
                    return end;
                }

                var m = start + (end - start) / 2;

                var c = comparer.Compare(value, list[m]);
                if (c == 0) {
                    list.Insert(m, value);
                    return m;
                }

                if (c < 0) {
                    end = m;
                } else {
                    start = m + 1;
                }
            }
        }
    }
}