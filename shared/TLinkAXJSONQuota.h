#pragma once
#include "TLinkAXWireOutput.h"

namespace TLinkAXJSONOutput {
static const size_t MaxJSONBytes = ((TLinkAXWireOutput::MaxSuccessWireBytes - 5) / 4) * 3;
class Quota {
    size_t size_ = 0;
    bool exceeded_ = false;
public:
    bool append(size_t bytes) {
        if (exceeded_) return false;
        if (bytes > MaxJSONBytes - size_) { exceeded_ = true; return false; }
        size_ += bytes;
        return true;
    }
    size_t size() const { return size_; }
    bool exceeded() const { return exceeded_; }
};
}
