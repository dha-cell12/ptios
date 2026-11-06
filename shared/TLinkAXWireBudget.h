#pragma once
#include "TLinkAXJSONStop.h"
#include "TLinkAXWireOutput.h"

namespace TLinkAXWireBudget {
enum class Admission {Ready,Stopped,TooLarge};
inline Admission Stop(const TLinkNativeBudgetPtr &budget) {
    const auto state = TLinkAXJSONOutput::ClassifyStop(budget);
    return !state.active ? Admission::Ready : (state.tooLarge ? Admission::TooLarge : Admission::Stopped);
}
// Recheck the original projection after opaque encoding/formatting. This is
// admission only: another producer may still consume output after this check.
inline Admission Check(const TLinkNativeBudgetPtr &budget, size_t wireBytes) {
    const auto before = Stop(budget);
    if (before != Admission::Ready) return before;
    if (wireBytes > TLinkAXWireOutput::MaxSuccessWireBytes) return Admission::TooLarge;
    if (budget && !budget->outputAllowed(wireBytes)) return Admission::TooLarge;
    return Stop(budget);
}
inline const char *FailureWire(Admission admission) {
    return admission == Admission::Stopped ? "-1;;ui_cancelled_or_timed_out\r\n" : "-1;;ui_response_too_large\r\n";
}
}
