#pragma once
#include "TLinkNativeBudget.h"

namespace TLinkAXJSONOutput {
struct StopState {
    bool active;
    bool tooLarge;
    bool cancelled;
    explicit StopState(TLinkNativeStop reason)
        : active(reason != TLinkNativeStop::None),
          tooLarge(reason == TLinkNativeStop::OutputLimit),
          cancelled(active && !tooLarge) {}
};
inline StopState ClassifyStop(const TLinkNativeBudgetPtr &budget) {
    return StopState(budget ? budget->reason() : TLinkNativeStop::None);
}
}
