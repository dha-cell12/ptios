#include "TLinkRootfullLicenseBuild.h"

#ifndef TLINK_LICENSE_FORCE_ENFORCEMENT
#define TLINK_LICENSE_FORCE_ENFORCEMENT 0
#endif

#if TLINK_LICENSE_FORCE_ENFORCEMENT
extern "C" __attribute__((used, visibility("default")))
const char TLinkRootfullLicenseBuildMarker[] = "rootfull_enforced_compile_time_v1";
#else
extern "C" __attribute__((used, visibility("default")))
const char TLinkRootfullLicenseBuildMarker[] = "rootfull_observe_compile_time_v1";
#endif

extern "C" const char *TLinkRootfullLicenseBuildMode(void)
{
    return TLinkRootfullLicenseBuildMarker;
}

extern "C" int TLinkRootfullLicenseBuildIsEnforced(void)
{
    return TLINK_LICENSE_FORCE_ENFORCEMENT ? 1 : 0;
}
