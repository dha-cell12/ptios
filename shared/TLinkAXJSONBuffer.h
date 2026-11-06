#pragma once
#include "TLinkAXJSONQuota.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <utility>

namespace TLinkAXJSONOutput {
inline void *ResizeJSONBytes(void *, void *bytes, size_t size) { return std::realloc(bytes, size); }
inline void FreeJSONBytes(void *, void *bytes) { std::free(bytes); }
struct Allocator {
    // resize follows realloc failure semantics; destroy must not throw.
    // A custom context must outlive every buffer/NSData owner using it.
    // resize follows realloc failure semantics; destroy must not throw.
    // A custom context must outlive every buffer/NSData owner using it.
    void *context;
    void *(*resize)(void *, void *, size_t);
    void (*destroy)(void *, void *);
    Allocator() : context(nullptr), resize(ResizeJSONBytes), destroy(FreeJSONBytes) {}
    Allocator(void *c, void *(*r)(void *, void *, size_t), void (*d)(void *, void *))
        : context(c), resize(r), destroy(d) {}
};
enum class BufferError {None,Limit,Allocation,Invalid,Sealed};
class Buffer {
    uint8_t *bytes_ = nullptr;
    size_t size_ = 0, capacity_ = 0;
    bool sealed_ = false;
    BufferError error_ = BufferError::None;
    Allocator allocator_;
public:
    explicit Buffer(Allocator allocator = Allocator()) : allocator_(allocator) {}
    Buffer(const Buffer &) = delete;
    Buffer &operator=(const Buffer &) = delete;
    Buffer(Buffer &&other) noexcept : bytes_(other.bytes_), size_(other.size_), capacity_(other.capacity_),
        sealed_(other.sealed_), error_(other.error_), allocator_(other.allocator_) {
        other.bytes_ = nullptr; other.size_ = other.capacity_ = 0; other.sealed_ = true;
    }
    ~Buffer() { release(); }
    // The writer supplies external chunks, never a range of this growable buffer.
    bool append(const uint8_t *bytes, size_t count) {
        if (error_ != BufferError::None) return false;
        if (sealed_) { error_ = BufferError::Sealed; return false; }
        if (count > MaxJSONBytes - size_) { error_ = BufferError::Limit; return false; }
        if (!bytes && count) { error_ = BufferError::Invalid; return false; }
        const size_t required = size_ + count;
        if (required > capacity_) {
            size_t capacity = capacity_ ? capacity_ : 128;
            while (capacity < required) capacity = capacity > MaxJSONBytes / 2 ? MaxJSONBytes : capacity * 2;
            void *next = allocator_.resize(allocator_.context, bytes_, capacity);
            if (!next) { error_ = BufferError::Allocation; return false; }
            bytes_ = static_cast<uint8_t *>(next); capacity_ = capacity;
        }
        if (count) std::memcpy(bytes_ + size_, bytes, count);
        size_ = required;
        return true;
    }
    bool seal() {
        if (sealed_ || error_ != BufferError::None) return false;
        sealed_ = true; return true;
    }
    void release() noexcept {
        if (bytes_) allocator_.destroy(allocator_.context, bytes_);
        bytes_ = nullptr; size_ = capacity_ = 0; sealed_ = true;
    }
    const uint8_t *data() const { return bytes_; }
    size_t size() const { return size_; }
    size_t capacity() const { return capacity_; }
    BufferError error() const { return error_; }
};
}
