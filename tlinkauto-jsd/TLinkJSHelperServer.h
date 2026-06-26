#import <Foundation/Foundation.h>

@interface TLinkJSHelperServer : NSObject
- (void)run;
- (NSDictionary *)runScriptDirectAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest;
@end
