#import <Foundation/Foundation.h>

// Starts the outbound WSS agent. Configuration is watched at runtime under
// config/tweak/config.plist -> remote_bridge, so streamd does not need a
// restart when the endpoint or token changes.
void TLinkStartRemoteBridgeAgent(void);

