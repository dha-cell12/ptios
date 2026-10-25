// Frozen owner assignment for pre-typed image handler oracles.
static void zx_applyImageOwner(ZXImageObject &image, NSArray *data, NSUInteger startIndex)
{
    image.ownerSessionId = zx_stringFromPart(data, startIndex, "");
    image.ownerRunId = zx_stringFromPart(data, startIndex + 1, "");
    image.ownerRuntime = zx_stringFromPart(data, startIndex + 2, "legacy");
}

