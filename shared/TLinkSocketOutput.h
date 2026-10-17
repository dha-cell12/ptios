#ifndef TLINK_SOCKET_OUTPUT_H
#define TLINK_SOCKET_OUTPUT_H
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <vector>
// Owned by the socket queue, including the shared total. No syscall under another lock.
class TLinkSocketOutput {
    struct Chunk {
        std::vector<uint8_t> bytes;
        size_t offset;
        uint64_t admitted;
        Chunk(const uint8_t *p, size_t n, uint64_t now) : bytes(p, p + n), offset(0), admitted(now) {}
    };
    std::deque<Chunk> chunks_;
    size_t owned_ = 0;
    uint64_t progress_ = 0;
public:
    static const size_t ClientLimit = 2 * 1024 * 1024;
    static const size_t GlobalLimit = 16 * 1024 * 1024;
    enum class Result { Empty, Pending, Failed };
    TLinkSocketOutput() = default;
    TLinkSocketOutput(const TLinkSocketOutput &) = delete;
    TLinkSocketOutput &operator=(const TLinkSocketOutput &) = delete;
    bool append(const uint8_t *bytes, size_t n, uint64_t now, size_t &total) {
        if (!n) return true;
        if (!bytes || n > ClientLimit - owned_ || total > GlobalLimit || n > GlobalLimit - total || chunks_.size() >= 128) return false;
        chunks_.emplace_back(bytes, n, now);
        if (!owned_) progress_ = now;
        owned_ += n; total += n; return true;
    }
    bool empty() const { return chunks_.empty(); }
    size_t owned() const { return owned_; }
    void clear(size_t &total) { total -= owned_; owned_ = 0; chunks_.clear(); }
    // writer returns 0 for EAGAIN/EINTR and -1 for fatal failure. At most four
    // nonblocking writes / 64 KiB per client per service turn. Never lose a suffix.
    template<class Writer> Result pump(uint64_t now, size_t &total, Writer writer) {
        if (empty()) return Result::Empty;
        if (now - progress_ >= 5000 || now - chunks_.front().admitted >= 30000) return Result::Failed;
        size_t quantum = 64 * 1024;
        for (unsigned call = 0; call < 4 && quantum && !chunks_.empty(); ++call) {
            Chunk &chunk = chunks_.front();
            const size_t want = std::min(quantum, chunk.bytes.size() - chunk.offset);
            const long long sent = writer(chunk.bytes.data() + chunk.offset, want);
            if (sent < 0 || static_cast<unsigned long long>(sent) > want) return Result::Failed;
            if (!sent) return Result::Pending;
            chunk.offset += static_cast<size_t>(sent); quantum -= static_cast<size_t>(sent); progress_ = now;
            if (chunk.offset == chunk.bytes.size()) {
                const size_t bytes = chunk.bytes.size();
                chunks_.pop_front(); owned_ -= bytes; total -= bytes;
            }
        }
        return empty() ? Result::Empty : Result::Pending;
    }
};
#endif
