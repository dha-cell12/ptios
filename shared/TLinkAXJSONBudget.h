#pragma once
#include "TLinkAXJSONStop.h"
#include "TLinkAXWireOutput.h"

namespace TLinkAXJSONOutput {
// A JSON prefix can only grow. If its eventual success framing already exceeds
// the remaining output allowance, no completed response can fit.
inline bool AdmitOutput(const TLinkNativeBudgetPtr &budget, size_t jsonBytes) {
    size_t wireBytes = 0;
    if (!TLinkAXWireOutput::SuccessSize(jsonBytes, wireBytes)) return false;
    return !budget || budget->outputAllowed(wireBytes);
}
}
