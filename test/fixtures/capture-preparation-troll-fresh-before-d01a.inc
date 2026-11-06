CGImageRef SCCreateScreenShotCGImage(void)
{
    @autoreleasepool {
        int width = 0;
        int height = 0;
        if (!SCDisplayPixelSize(&width, &height)) return NULL;

        errno = 0;
        IOSurfaceRef surface = SCCreateBGRAIOSurface(width, height);
        if (!surface) return NULL;

        CGImageRef image = NULL;
        IOSurfaceLock(surface, 0, NULL);
        CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
        image = UICreateCGImageFromIOSurface(surface);
        IOSurfaceUnlock(surface, 0, NULL);
        CFRelease(surface);
        return image; // retained by UICreateCGImageFromIOSurface
    }
}
