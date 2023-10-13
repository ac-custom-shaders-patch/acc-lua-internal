using System;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class MemoryPool<T> {
        private readonly string _name;
        private readonly ConcurrentSimpleStack<T[]> _stack = new ConcurrentSimpleStack<T[]>();
        private int _size;
        private int _sizeCandidate;
        private readonly bool _growMode;

        public MemoryPool(string name, int size, bool growMode = false) {
            _name = name;
            _size = size;
            _growMode = growMode;
        }

        public T[] GetOrAllocate(bool clearData = false) {
            if (_stack.Pop(out var ret)) {
                if (clearData) {
                    Array.Clear(ret, 0, ret.Length);
                }
                return ret;
            }
            Debug.Log($"New allocation on {_name} pool ({typeof(T).Name}[]): {_size} items");
            return new T[_size];
        }

        public T[] GetOrAllocate(int length) {
            if (_growMode ? length > _size : _size != length) {
                if (length < 64) {
                    return new T[length];
                }

                if (_sizeCandidate == length) {
                    Debug.Log($"Changing size of {_name} pool from {_size} to {length}");
                    _size = length;
                    _stack.Clear();
                } else {
                    _sizeCandidate = length;
                    return new T[length];
                }
            }
            return GetOrAllocate();
        }

        public void Release(ref T[] data) {
            if (data == null || data.Length != _size) return;
            _stack.Push(data);
            data = null;
        }
    }
}