// Private immutable NSString adapter for the existing JSON-to-writeText route.
// Keep normal string semantics while reusing the exact encoded UTF8 snapshot.
#ifndef TLINK_PREPARED_JSON_TEXT_INC
#define TLINK_PREPARED_JSON_TEXT_INC
#import <Foundation/Foundation.h>

@interface TLinkPreparedJSONText : NSString {
    NSData *_encodedJSON;
    NSString *_decodedJSON;
}
- (instancetype)initWithJSONData:(NSData *)data;
@end

@implementation TLinkPreparedJSONText
- (instancetype)initWithJSONData:(NSData *)data
{
    self = [super init];
    if (self) {
        _encodedJSON = [data copy];
        _decodedJSON = [[NSString alloc] initWithData:_encodedJSON encoding:NSUTF8StringEncoding];
        if (!_decodedJSON) return nil;
        // Preserve NSString's encoding normalization (for example BOM handling)
        // instead of writing a byte sequence its UTF8 writer would not retain.
        if ([_decodedJSON lengthOfBytesUsingEncoding:NSUTF8StringEncoding] != _encodedJSON.length) return (id)_decodedJSON;
    }
    return self;
}
- (NSUInteger)length { return _decodedJSON.length; }
- (unichar)characterAtIndex:(NSUInteger)index { return [_decodedJSON characterAtIndex:index]; }
- (void)getCharacters:(unichar *)buffer range:(NSRange)range { [_decodedJSON getCharacters:buffer range:range]; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return self; }
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding
{
    if (encoding == NSUTF8StringEncoding) return _encodedJSON.length;
    return [_decodedJSON lengthOfBytesUsingEncoding:encoding];
}
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding
{
    if (encoding == NSUTF8StringEncoding) return _encodedJSON;
    return [_decodedJSON dataUsingEncoding:encoding];
}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomic encoding:(NSStringEncoding)encoding error:(NSError **)error
{
    if (encoding != NSUTF8StringEncoding) return [_decodedJSON writeToFile:path atomically:atomic encoding:encoding error:error];
    return [_encodedJSON writeToFile:path options:(atomic ? NSDataWritingAtomic : (NSDataWritingOptions)0) error:error];
}
@end
#endif
