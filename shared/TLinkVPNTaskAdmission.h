#ifndef TLINK_VPN_TASK_ADMISSION_H
#define TLINK_VPN_TASK_ADMISSION_H
#include "TLinkC01Ingress.h"
static const size_t TLinkVPNTaskPendingLimit=2;
inline bool TLinkVPNTaskPayload(const uint8_t *bytes,size_t length){
    return bytes&&length>=2&&bytes[0]=='5'&&bytes[1]=='9';
}
// Socket-owner counts include running, queued and completion-pending work.
// VPN uses the existing ordinary allowance, never the two reserved image slots.
inline bool TLinkVPNTaskLaneAvailable(bool vpn,bool image,size_t pending,size_t images,size_t vpns){
    if(vpns>TLinkVPNTaskPendingLimit||images>pending||vpns>pending-images||(vpn&&image))return false;
    return TLinkC01LaneAvailable(image,pending,images)&&(!vpn||vpns<TLinkVPNTaskPendingLimit);
}
#endif
