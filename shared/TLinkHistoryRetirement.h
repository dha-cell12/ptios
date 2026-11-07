#pragma once
#include <cstddef>
#include <cstdint>

// Plan only: the caller owns records, mutation and commit ordering.
struct TLinkHistoryRetirementPlan {
    size_t total,keep,retired,hint;
    TLinkHistoryRetirementPlan(size_t count,size_t limit)
        :total(count),keep(count<limit?count:limit),retired(count-keep),hint(retired<limit?retired:limit){}
    size_t index(size_t step) const {return step<retired?total-1-step:SIZE_MAX;}
};
