// Frozen 86c0974 OCR languages compatibility oracle.
static NSString *zx_tessCheckLangs(void)
{
    NSString *dir = [kZXTessdataRoot stringByAppendingPathComponent:@"tessdata"];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *langs = [NSMutableArray array];
    for (NSString *file in files ?: @[]) {
        if ([[file pathExtension] isEqualToString:@"traineddata"]) {
            [langs addObject:[file stringByDeletingPathExtension]];
        }
    }
    [langs sortUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"check_langs;;%@", zx_tessBase64([langs componentsJoinedByString:@","])];
}

