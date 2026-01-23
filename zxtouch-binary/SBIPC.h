#ifndef ZXTOUCHD_SBIPC_H
#define ZXTOUCHD_SBIPC_H

#import <Foundation/Foundation.h>

/// Send a "TASK::"-prefixed command to SpringBoard's CFMessagePort.
///
/// @param taskLine The raw task line as it would be sent by the socket client, e.g. "35" or "35;;args".
/// @return SpringBoard response string (UTF-8), or nil on failure.
NSString *ZXSendSpringBoardTask(NSString *taskLine, NSTimeInterval timeoutSeconds);

#endif
