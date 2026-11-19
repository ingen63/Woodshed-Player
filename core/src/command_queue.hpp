// Begrenzte Lock-free-Queue für mehrere Erzeuger und Verbraucher (Verfahren nach D. Vyukov).
// Speicher wird nur im Konstruktor reserviert; push()/pop() sperren nie und reservieren nichts,
// dürfen also im Audio-Thread laufen. Ist die Queue voll, liefert push() false.
#pragma once

#include <atomic>
#include <cstddef>
#include <memory>

namespace wp {

template <typename T> class CommandQueue {
public:
  // capacity wird auf die nächste Zweierpotenz aufgerundet (mindestens 2).
  explicit CommandQueue(size_t capacity) {
    size_t n = 2;
    while (n < capacity)
      n <<= 1;
    mask_ = n - 1;
    cells_ = std::make_unique<Cell[]>(n);
    for (size_t i = 0; i < n; ++i)
      cells_[i].seq.store(i, std::memory_order_relaxed);
  }

  CommandQueue(const CommandQueue &) = delete;
  CommandQueue &operator=(const CommandQueue &) = delete;

  size_t capacity() const { return mask_ + 1; }

  bool push(const T &value) {
    size_t pos = tail_.load(std::memory_order_relaxed);
    for (;;) {
      Cell &c = cells_[pos & mask_];
      const size_t seq = c.seq.load(std::memory_order_acquire);
      const auto diff = static_cast<std::ptrdiff_t>(seq) - static_cast<std::ptrdiff_t>(pos);
      if (diff == 0) {
        if (tail_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
          c.value = value;
          c.seq.store(pos + 1, std::memory_order_release);
          return true;
        }
      } else if (diff < 0) {
        return false; // voll
      } else {
        pos = tail_.load(std::memory_order_relaxed);
      }
    }
  }

  bool pop(T &value) {
    size_t pos = head_.load(std::memory_order_relaxed);
    for (;;) {
      Cell &c = cells_[pos & mask_];
      const size_t seq = c.seq.load(std::memory_order_acquire);
      const auto diff = static_cast<std::ptrdiff_t>(seq) - static_cast<std::ptrdiff_t>(pos + 1);
      if (diff == 0) {
        if (head_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
          value = c.value;
          c.seq.store(pos + mask_ + 1, std::memory_order_release);
          return true;
        }
      } else if (diff < 0) {
        return false; // leer
      } else {
        pos = head_.load(std::memory_order_relaxed);
      }
    }
  }

private:
  static_assert(std::atomic<size_t>::is_always_lock_free, "atomic<size_t> must be lock-free");

  struct Cell {
    std::atomic<size_t> seq{0};
    T value{};
  };

  std::unique_ptr<Cell[]> cells_;
  size_t mask_ = 0;
  alignas(64) std::atomic<size_t> tail_{0};
  alignas(64) std::atomic<size_t> head_{0};
};

} // namespace wp
