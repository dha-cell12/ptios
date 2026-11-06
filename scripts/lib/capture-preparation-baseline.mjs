import assert from 'node:assert/strict';
import{readFileSync}from'node:fs';
import{createHash}from'node:crypto';
const spec={
  "root": {
    "path": "pccontrol/Screen.xm",
    "hash": "abc05ba048197ee3589fe97922b257fc5073eb2e4c796064d91cd46b77c26b91",
    "includes": [
      "#include \"../shared/TLinkCapturePreparation.h\"\n",
      "#include \"../shared/TLinkCaptureOwnership.h\"\n"
    ],
    "parts": [
      {
        "kind": "core",
        "start": "struct TLinkCaptureGeometry {",
        "end": "// END capture ownership core.",
        "current": "struct TLinkCaptureGeometry {\n    size_t width;\n    size_t height;\n    size_t bytesPerRow;\n    size_t allocationSize;\n};\n\nstatic size_t zx_captureAlignedRowBytes(size_t width)\n{\n    if (width == 0 || width > (SIZE_MAX - 31) / 4) return 0;\n    return (width * 4 + 31) & ~(size_t)31;\n}\n\nstatic bool zx_captureGeometry(CGFloat boundsWidth, CGFloat boundsHeight, CGFloat scale,\n                               bool rotateIPad, TLinkCaptureGeometry *out)\n{\n    if (!out) return false;\n    *out = {};\n    if (!isfinite(boundsWidth) || !isfinite(boundsHeight) || !isfinite(scale) ||\n        boundsWidth <= 0 || boundsHeight <= 0 || scale <= 0) return false;\n    const CGFloat pixelWidth = boundsWidth * scale;\n    const CGFloat pixelHeight = boundsHeight * scale;\n    if (!isfinite(pixelWidth) || !isfinite(pixelHeight) || pixelWidth < 1 || pixelHeight < 1 ||\n        pixelWidth > INT_MAX || pixelHeight > INT_MAX) return false;\n    size_t width = (size_t)pixelWidth;\n    size_t height = (size_t)pixelHeight;\n    if ((rotateIPad && width < height) || (!rotateIPad && width > height)) {\n        size_t temporary = width;\n        width = height;\n        height = temporary;\n    }\n    const size_t bytesPerRow = zx_captureAlignedRowBytes(width);\n    if (bytesPerRow == 0 || height > SIZE_MAX / bytesPerRow) return false;\n    *out = {width, height, bytesPerRow, bytesPerRow * height};\n    return true;\n}\n\n// Borrow source and its color space for the whole context lifetime; return an owned image.\nstatic CGImageRef zx_captureRotatedImage(CGImageRef source)\n{\n    if (!source) return NULL;\n    const size_t width = CGImageGetWidth(source);\n    const size_t height = CGImageGetHeight(source);\n    CGColorSpaceRef colorSpace = CGImageGetColorSpace(source); // Get-rule reference, never release here.\n    const size_t bytesPerRow = zx_captureAlignedRowBytes(height); // Rotated output width is source height.\n    if (width == 0 || height == 0 || !colorSpace || CGImageGetBitsPerComponent(source) != 8 ||\n        bytesPerRow == 0 || width > SIZE_MAX / bytesPerRow) return NULL;\n    CGContextRef bitmap = CGBitmapContextCreate(NULL, height, width, 8, bytesPerRow,\n                                                colorSpace, kCGImageAlphaPremultipliedFirst);\n    if (!bitmap) return NULL;\n    TLinkCaptureOwnership::Scoped<CGContextRef,decltype(&CGContextRelease)> bitmapOwner(bitmap,&CGContextRelease);\n    const CGFloat radians = -90.0 * (M_PI / 180.0);\n    CGContextTranslateCTM(bitmap, 0.5 * height, 0.5 * width);\n    CGContextRotateCTM(bitmap, radians);\n    CGContextTranslateCTM(bitmap, -0.5 * width, -0.5 * height);\n    CGContextDrawImage(bitmap, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);\n    CGImageRef rotated = CGBitmapContextCreateImage(bitmap);\n    return rotated;\n}\n\nstruct TLinkRootCaptureAPI {\n    using Surface=IOSurfaceRef;using Image=CGImageRef;\n    bool rotateIPad;\n    explicit TLinkRootCaptureAPI(bool rotate):rotateIPad(rotate){}\n    bool lock(Surface value){return IOSurfaceLock(value,0,NULL)==KERN_SUCCESS;}\n    bool unlock(Surface value){return IOSurfaceUnlock(value,0,NULL)==KERN_SUCCESS;}\n    void dropSurface(Surface value){CFRelease(value);}\n    void dropImage(Image value){CGImageRelease(value);}\n    void render(Surface value){CARenderServerRenderDisplay(0,CFSTR(\"LCD\"),value,0,0);}\n    Image createImage(Surface value){return UICreateCGImageFromIOSurface(value);}\n    bool validImage(Image value){return CGImageGetWidth(value)>0&&CGImageGetHeight(value)>0;}\n    bool rotates()const{return rotateIPad;}\n    Image rotate(Image value){return zx_captureRotatedImage(value);}\n};\n\nstatic CGImageRef zx_captureSurfaceImage(CFDictionaryRef properties, bool rotateIPad)\n{\n    TLinkRootCaptureAPI api(rotateIPad);\n    return TLinkCaptureOwnership::Fresh(IOSurfaceCreate(properties),api);\n}\n"
      },
      {
        "kind": "entry",
        "start": "static CGImageRef zx_captureScreenCGImageRef(void)\n{",
        "end": "+ (BOOL)keepScreen:",
        "current": "static CGImageRef zx_captureScreenCGImageRef(void)\n{\n    @autoreleasepool {\n        UIScreen *screen = [UIScreen mainScreen];\n        CGSize screenSize = screen.bounds.size;\n        static TLinkCapturePlan::BoolMemo deviceMemo;\n        const bool rotateIPad = TLinkCapturePreparation::RotateIPad(deviceMemo, []{return getDeviceName();});\n        TLinkCaptureGeometry geometry;\n        if (!zx_captureGeometry(screenSize.width, screenSize.height, screen.scale, rotateIPad, &geometry)) return NULL;\n        static TLinkCapturePreparation::Properties propertyMemo;\n        TLinkCapturePlan::Key key(geometry.width,geometry.height,geometry.bytesPerRow,geometry.allocationSize,true,false);\n        NSDictionary *properties=propertyMemo.get(key);\n        if (!properties) return NULL;\n        return zx_captureSurfaceImage((__bridge CFDictionaryRef)properties, rotateIPad);\n    }\n}\n\n"
      }
    ]
  },
  "common": {
    "path": "pccontrol/Common.xm",
    "hash": "eb556ed2b27ac971914c9a92ceae010825af57afcb65fb1af930acb366542615",
    "includes": [
      "#include \"../shared/TLinkCapturePlan.h\"\n"
    ],
    "parts": [
      {
        "kind": "device",
        "start": "NSString* getDeviceName()",
        "end": "/*\nround up number",
        "current": "NSString* getDeviceName()\n{\n    struct utsname systemInfo = {};\n    if (uname(&systemInfo) != 0) return nil;\n    size_t length = TLinkCapturePlan::MachineLength(systemInfo.machine,sizeof(systemInfo.machine));\n    if (!length) return nil;\n    return [[NSString alloc] initWithBytes:systemInfo.machine length:length encoding:NSUTF8StringEncoding];\n}\n\n"
      }
    ]
  },
  "troll": {
    "path": "stream-app/streamd/StreamCaptureSource.mm",
    "hash": "23e15b6626485a2cc248d5fdae35b56a09ee71dfff3b9f5c1f370e6c749738f9",
    "includes": [
      "#include \"../../shared/TLinkCapturePreparation.h\"\n",
      "#include \"../../shared/TLinkCaptureOwnership.h\"\n"
    ],
    "parts": [
      {
        "kind": "surface",
        "start": "static BOOL SCDisplayPixelSize(",
        "end": "static IOSurfaceRef SCStagingSurfaceLocked(",
        "current": "static BOOL SCDisplayPixelSize(int *outWidth, int *outHeight)\n{\n    UIScreen *screen=[UIScreen mainScreen];\n    CGFloat scale=screen.scale;\n    CGSize bounds=screen.bounds.size;\n    int width=0,height=0;\n    if (!TLinkCapturePlan::Display(bounds.width,bounds.height,scale,width,height)) return NO;\n    if (outWidth) *outWidth=width;\n    if (outHeight) *outHeight=height;\n    return YES;\n}\n\nstatic IOSurfaceRef SCCreateBGRAIOSurface(int width, int height)\n{\n    if (width<=0 || height<=0) return NULL;\n    SCResolveSurfaceAcceleratorSymbols();\n    const size_t minimumBytesPerRow=(size_t)width*4;\n    const size_t alignedBytesPerRow=sSCIOSurfaceAlignProperty\n        ? sSCIOSurfaceAlignProperty(CFSTR(\"IOSurfaceBytesPerRow\"),minimumBytesPerRow) : 0;\n    TLinkCapturePlan::Key key;\n    if (!TLinkCapturePlan::Row(width,height,alignedBytesPerRow,key)) return NULL;\n    static TLinkCapturePreparation::Properties propertyMemo;\n    NSDictionary *properties=propertyMemo.get(key);\n    if (!properties) return NULL;\n    IOSurfaceRef surface=IOSurfaceCreate((__bridge CFDictionaryRef)properties);\n    if (!surface) {\n        key.global=false;\n        properties=propertyMemo.get(key);\n        if (properties) surface=IOSurfaceCreate((__bridge CFDictionaryRef)properties);\n    }\n    return surface;\n}\n\n"
      },
      {
        "kind": "fresh",
        "start": "struct SCFreshCaptureAPI {",
        "end": null,
        "current": "struct SCFreshCaptureAPI {\n    using Surface=IOSurfaceRef;using Image=CGImageRef;\n    bool lock(Surface value){return IOSurfaceLock(value,0,NULL)==KERN_SUCCESS;}\n    bool unlock(Surface value){return IOSurfaceUnlock(value,0,NULL)==KERN_SUCCESS;}\n    void dropSurface(Surface value){CFRelease(value);}\n    void dropImage(Image value){CGImageRelease(value);}\n    void render(Surface value){CARenderServerRenderDisplay(0,CFSTR(\"LCD\"),value,0,0);}\n    Image createImage(Surface value){return UICreateCGImageFromIOSurface(value);}\n    bool validImage(Image value){return CGImageGetWidth(value)>0&&CGImageGetHeight(value)>0;}\n    bool rotates()const{return false;}\n    Image rotate(Image value){(void)value;return NULL;}\n};\n\nCGImageRef SCCreateScreenShotCGImage(void)\n{\n    @autoreleasepool {\n        int width=0,height=0;\n        if (!SCDisplayPixelSize(&width,&height)) return NULL;\n        errno=0;\n        SCFreshCaptureAPI api;\n        return TLinkCaptureOwnership::Fresh(SCCreateBGRAIOSurface(width,height),api);\n    }\n}\n"
      }
    ]
  }
};
export function captureBefore(kind,part){return readFileSync(new URL('../../test/fixtures/capture-preparation-'+kind+'-'+part+'-before-d01a.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function capturePart(source,kind,part){const p=spec[kind].parts.find(p=>p.kind===part),a=source.indexOf(p.start),b=p.end?source.indexOf(p.end,a):source.length;assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreCapturePreparation(source,kind){const p=spec[kind];for(const inc of p.includes){assert.equal(source.split(inc).length-1,1);source=source.replace(inc,'');}for(const part of p.parts){const body=capturePart(source,kind,part.kind);assert.equal(body,part.current);source=source.replace(body,captureBefore(kind,part.kind));}if(kind==='troll'){assert.ok(!source.includes('static int SCRoundUp('));source=source.replace('static void SCReleaseCaptureSurfacesLocked(',captureBefore('troll','round')+'static void SCReleaseCaptureSurfacesLocked(');}assert.equal(createHash('sha256').update(source).digest('hex'),p.hash,'complete preceding capture/model source');return source;}
const headerHashes={"TLinkCapturePlan.h": "4bf5293788a031bdee07562bed689260972edeba96c055dd29abc960203026a9", "TLinkCapturePreparation.h": "49ae657235341d3ac8df9004f0259133172d40d939032669fea1320155a7e5c6", "TLinkCaptureOwnership.h": "8772901fe60fc57a8f6a79607b6f7139150b26bd935949ba30fc45f3a7d4dc38"};
export function checkCaptureHeader(name,source){assert.equal(createHash("sha256").update(source).digest("hex"),headerHashes[name],name+" complete checked capture helper");}
