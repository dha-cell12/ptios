#include <climits>
#include "../../shared/TLinkVisionPolicy.h"
#include "../../shared/TLinkNativeDispatch.h"
#import "VKOcrManager.h"
#ifndef ZX_DAEMON
#import "../Screen.h"
#endif
#include "../Common.h"


@implementation VKOcrManager
{
    BOOL inProgress;

    TLinkVisionContextPtr context;
    NSString *setupFailure;

    VNImageRequestHandler* requestHandler;
    VNRecognizeTextRequest* request;

    CIImage *img;
    CGRect recognizeRect;
}


- (id)initWithCIImage:(CIImage*)image area:(CGRect)aarea orientation:(int)orientation {
    self = [super init];
    if (self)
    {
        context=TLinkVisionSlot();
        if(!context)context=std::make_shared<TLinkVisionContext>(TLinkCurrentNativeBudget());
        if(!context->admitted()){setupFailure=@"vision_busy";return self;}
        if(context->stopped()){setupFailure=@"vision_cancelled_or_timed_out";return self;}
        if(!image||!std::isfinite(image.extent.origin.x)||!std::isfinite(image.extent.origin.y)||
            !std::isfinite(image.extent.size.width)||!std::isfinite(image.extent.size.height)||
            image.extent.size.width<=0||image.extent.size.height<=0||image.extent.size.width>8192||image.extent.size.height>8192||
            std::ceil(image.extent.size.width)*std::ceil(image.extent.size.height)>8388608) {
            setupFailure=@"vision_roi_invalid_or_too_large";return self;
        }
        int after = kCGImagePropertyOrientationUp;
        if (orientation == 4)
        {
            after = kCGImagePropertyOrientationRight;
        }
        else if (orientation == 3)
        {
            after = kCGImagePropertyOrientationLeft;
        }
        else if (orientation == 2)
        {
            after = kCGImagePropertyOrientationDown;
        }

        image = [image imageByApplyingOrientation:after];
        
        img = image;

        CGFloat imageWidth = image.extent.size.width;
        CGFloat imageHeight = image.extent.size.height;



        TLinkVisionROI roi;
        if(!image||!TLinkVisionPlan(imageWidth,imageHeight,aarea.origin.x,aarea.origin.y,aarea.size.width,aarea.size.height,roi)) {
            setupFailure=@"vision_roi_invalid_or_too_large";return self;
        }
        recognizeRect=CGRectMake(roi.x,roi.y,roi.width,roi.height);
        CGRect crop=CGRectMake(image.extent.origin.x+roi.x,image.extent.origin.y+imageHeight-roi.y-roi.height,roi.width,roi.height);
        requestHandler=[[VNImageRequestHandler alloc] initWithCIImage:[image imageByCroppingToRect:crop] options:nil];
        // Read synchronous results directly; no request -> completion -> manager cycle.
        request=[[VNRecognizeTextRequest alloc] init];

        // Preserve the legacy Vision revision selection by OS version.
        if (SYSTEM_VERSION_LESS_THAN(@"14.0"))
        {
            request.revision = 1;
        }
        else
        {
            request.revision = 2;
        }
    }
    return self;
}

- (id)initWithImagePath:(NSString*)path area:(CGRect)aarea orientation:(int)orientation {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    CIImage *image = [CIImage imageWithContentsOfURL:fileURL];
    return [self initWithCIImage:image area:aarea orientation:orientation];
}

- (id)initWithCGImage:(CGImageRef)cgimage area:(CGRect)aarea orientation:(int)orientation {
    CIImage *image = [[CIImage alloc] initWithCGImage:cgimage];
    return [self initWithCIImage:image area:aarea orientation:orientation];
}

/*
Return the string from a area
*/
- (NSString*)recognize:(NSError**)error{
    @synchronized(self) {
        if(inProgress){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_instance_busy\r\n"}];return nil;}
        inProgress=true;
    }
    dispatch_source_t monitor=nil;dispatch_queue_t monitorQueue=nil;
    @try {
        if(!context||setupFailure||context->stopped()) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",setupFailure?:(context?@"vision_cancelled_or_timed_out":@"vision_not_initialized")]}];
            return nil;
        }
        std::weak_ptr<TLinkVisionContext> budget=context;
        VNRecognizeTextRequest *activeRequest=request;
        monitorQueue=dispatch_queue_create("com.tlinkauto.vision.cancel",DISPATCH_QUEUE_SERIAL);
        monitor=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,monitorQueue);
        if(!monitor){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_monitor_failed\r\n"}];return nil;}
        dispatch_source_set_timer(monitor,dispatch_time(DISPATCH_TIME_NOW,0),10*NSEC_PER_MSEC,NSEC_PER_MSEC);
        dispatch_source_set_event_handler(monitor,^{auto current=budget.lock();if(current&&current->stopped())[activeRequest cancel];});
        dispatch_resume(monitor);
        NSError *failure=nil;
        BOOL performed=[requestHandler performRequests:@[request] error:&failure];
        if(context->stopped()) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_cancelled_or_timed_out\r\n"}];return nil;
        }
        if(!performed||failure) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_perform_failed\r\n"}];return nil;
        }
        NSArray *observations=request.results;
        if(observations.count>4096) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_observation_limit\r\n"}];return nil;
        }
        NSMutableArray<NSString *> *lines=[NSMutableArray array];size_t bytes=0;
        for(VNRecognizedTextObservation *observation in observations) {
            if(context->stopped())break;
            VNRecognizedText *text=[observation topCandidates:1].firstObject;
            if(!text||text.string.length==0)continue;
            VNRectangleObservation *box=[text boundingBoxForRange:NSMakeRange(0,text.string.length) error:nil];
            if(!box)continue;
            float width=(box.topRight.x-box.topLeft.x)*recognizeRect.size.width;
            float height=fabs(box.topLeft.y-box.bottomLeft.y)*recognizeRect.size.height;
            float x=box.topLeft.x*recognizeRect.size.width+recognizeRect.origin.x;
            float y=(1-box.topLeft.y)*recognizeRect.size.height+recognizeRect.origin.y;
            if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(width)||!std::isfinite(height)||
                fabs(x)>INT_MAX/2||fabs(y)>INT_MAX/2||fabs(width)>INT_MAX/2||fabs(height)>INT_MAX/2)continue;
            const size_t textBytes=[text.string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if(textBytes>1048576-bytes){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_output_limit\r\n"}];return nil;}
            NSString *line=[NSString stringWithFormat:@"%@,,%d,,%d,,%d,,%d",text.string,(int)x,(int)y,(int)width,(int)height];
            bytes+=[line lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+(lines.count?2:0);
            if(!context->outputAllowed(bytes)){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_output_limit\r\n"}];return nil;}
            [lines addObject:line];
        }
        if(context->stopped()){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_cancelled_or_timed_out\r\n"}];return nil;}
        return [lines componentsJoinedByString:@";;"];
    } @catch(NSException *exception) {
        (void)exception;if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_operation_failed\r\n"}];return nil;
    } @finally {
        if(monitor){dispatch_source_cancel(monitor);dispatch_sync(monitorQueue,^{});}
        @synchronized(self){inProgress=false;}
    }
}

/*
Return area that contain text
*/
- (NSArray*)areasOfText {
    return request.results?:@[];
}

#ifndef ZX_DAEMON
- (void)outputDebugImage:(NSString*)imagePath error:(NSError**)error{
    @synchronized(self){if(inProgress){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_instance_busy\r\n"}];return;}inProgress=true;}
    @try {
        if(!context||setupFailure) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",setupFailure?:@"vision_not_initialized"]}];return;
        }
        if(context->stopped())return;
        NSError *failure=nil;
        UIImage *image=[self drawDebugOutputfromArray:request.results error:&failure];
        if(failure){if(error)*error=failure;return;}
        if(!image||context->stopped()) {
            if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:context->stopped()?@"-1;;vision_cancelled_or_timed_out\r\n":@"-1;;vision_debug_render_failed\r\n"}];return;
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:[imagePath stringByDeletingLastPathComponent] withIntermediateDirectories:true attributes:nil error:&failure];
        if(!failure){NSData *data=UIImageJPEGRepresentation(image,0.7);if(!data||![data writeToFile:imagePath options:NSDataWritingAtomic error:&failure]){if(!failure)failure=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_debug_write_failed\r\n"}];}}
        if(failure&&error)*error=failure;
    } @finally {@synchronized(self){inProgress=false;}}
}

- (void)drawRectangle:(CGRect)rect inContext:(CGContextRef)ctx withColor:(UIColor*)color {
    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;
    CGFloat x = rect.origin.x;
    CGFloat y = rect.origin.y;

    CGPoint topLeft = rect.origin;
    CGPoint topRight = CGPointMake(x + width, y);
    CGPoint bottomLeft = CGPointMake(x, y + height);
    CGPoint bottomRight = CGPointMake(x + width, y + height);

    CGContextSetStrokeColorWithColor(ctx, color.CGColor);

    CGContextMoveToPoint(ctx, topLeft.x, topLeft.y);
    CGContextAddLineToPoint(ctx, topRight.x, topRight.y);
    CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y);
    CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y);
    CGContextAddLineToPoint(ctx, topLeft.x, topLeft.y);

    CGContextDrawPath(ctx, kCGPathStroke);
}


-(UIImage *)drawDebugOutputfromArray:(NSArray<VNRecognizedTextObservation*>*)arr error:(NSError**)error{
    if(arr.count>4096){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_observation_limit\r\n"}];return nil;}
    // reformat rect (don't know why there is size differnt here)

    UIImage* image = [[UIImage alloc] initWithCIImage:img];
    
    CGFloat imageAbsoluteWidth = image.size.width;
    CGFloat imageAbsoluteHeight = image.size.height;

    CGRect wholeImageRect = CGRectMake(0, 0, imageAbsoluteWidth, imageAbsoluteHeight);

    // begin a graphics context of sufficient size
    UIGraphicsBeginImageContextWithOptions(image.size, false, 1);
    @try { // CGSizeMake(imageAbsoluteWidth, imageAbsoluteHeight)
 
	// draw original image into the context
	[image drawInRect:wholeImageRect];
 
	// get the context for CoreGraphics
	CGContextRef ctx = UIGraphicsGetCurrentContext();
    if(!ctx){if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;vision_debug_context_failed\r\n"}];return nil;}
 
    // draw match rectangle
    [self drawRectangle:recognizeRect inContext:ctx withColor:[UIColor redColor]];

    [[UIColor redColor] setFill]; // set color
    [[NSString stringWithFormat:@"Rect:(%d, %d, %d, %d)", (int)recognizeRect.origin.x, (int)recognizeRect.origin.y, (int)recognizeRect.size.width, (int)recognizeRect.size.height] drawInRect:CGRectIntegral(recognizeRect) withFont:[UIFont boldSystemFontOfSize:30]]; 

    for (VNRecognizedTextObservation* i in arr)
    {
        if(context->stopped())return nil;
        VNRecognizedText* text = [i topCandidates:1].firstObject;
        if(!text||text.string.length==0)continue;
        NSString* textString = [text string];
            
        NSError *err = nil;
        VNRectangleObservation* boundingBox = [text boundingBoxForRange:NSMakeRange(0, [textString length]) error:&err];

        if (err || !boundingBox)
        {
            NSLog(@"com.tlinkauto.springboard: unable to output debug image for text recognization. Error: %@", err);
            if(error)*error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unable to output debug image for text recognization. Error: %@", err]}];
            return nil;
        }

        //test = [self drawTextRectangle:CGRectMake(100, 100, 100, 100) andText:@"test"];

        float rectWidth = (boundingBox.topRight.x - boundingBox.topLeft.x) * recognizeRect.size.width;
        float rectHeight = fabs(boundingBox.topLeft.y - boundingBox.bottomLeft.y) * recognizeRect.size.height;
        float rectx = boundingBox.topLeft.x * recognizeRect.size.width + recognizeRect.origin.x;
        float recty = (1 - boundingBox.topLeft.y) * recognizeRect.size.height + recognizeRect.origin.y;

        if(!std::isfinite(rectx)||!std::isfinite(recty)||!std::isfinite(rectWidth)||!std::isfinite(rectHeight))continue;
        CGRect rect = CGRectMake(rectx, recty, rectWidth, rectHeight);
        //NSLog(@"com.tlinkauto.springboard: rect: recognizeRect: %f, boundingBox: %f", recognizeRect.origin.y, boundingBox.topLeft.y);
        // draw text rectangles
        [self drawRectangle:rect inContext:ctx withColor:[UIColor greenColor]];
        
        // draw filled rectangle
        CGContextSetFillColorWithColor(ctx, [[UIColor redColor] colorWithAlphaComponent:0.3].CGColor); // set color
        CGContextFillRect(ctx, rect);

        // draw text
        [[UIColor redColor] setFill]; // set color
        UIFont *font = [UIFont boldSystemFontOfSize:20]; //set font size
        rect.origin.y = rect.origin.y + rect.size.height; // draw
        [textString drawInRect:CGRectIntegral(rect) withFont:font]; 

        //NSLog(@"com.tlinkauto.springboard: string: %@, topLeft: %f, topright:%f", textString, boundingBox.topLeft.x, boundingBox.topRight.x);

    }


 
	// make image out of bitmap context
	UIImage *retImage = UIGraphicsGetImageFromCurrentImageContext();
 
	// free the context
	return retImage;
    } @finally {UIGraphicsEndImageContext();}
}




#else
- (void)outputDebugImage:(NSString*)imagePath error:(NSError**)error{ }
- (UIImage *)drawDebugOutputfromArray:(NSArray*)arr error:(NSError**)error{ return nil; }
#endif
- (void)setMinimumHeight:(float)height {
    request.minimumTextHeight = height;
}

- (void)setCustomWords:(NSArray*)customWords {
    request.customWords = customWords;
}

- (void)setRecognitionLevel:(VNRequestTextRecognitionLevel)level {
    request.recognitionLevel = level;
}

- (void)setLanguages:(NSArray*)languages {
    request.recognitionLanguages = languages;
}

- (void)setCorrection:(BOOL)correct {
    request.usesLanguageCorrection = correct;
}

@end
