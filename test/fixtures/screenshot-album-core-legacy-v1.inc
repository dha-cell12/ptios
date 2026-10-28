// Frozen a97c1b0 screenshot album compatibility oracle.
+ (PHAssetCollection*)fetchTLinkautoAlbum
{
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", kTLinkautoAlbumName];
    PHFetchResult<PHAssetCollection*> *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                                         subtype:PHAssetCollectionSubtypeAlbumRegular
                                                                                         options:fetchOptions];
    return result.firstObject;
}

+ (PHAssetCollection*)ensureTLinkautoAlbumWithError:(NSError**)error
{
    if (!NSClassFromString(@"PHPhotoLibrary"))
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Photos framework is unavailable.\r\n"}];
        }
        return nil;
    }

    PHAssetCollection *album = [self fetchTLinkautoAlbum];
    if (album)
    {
        return album;
    }

    NSError *creationError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:kTLinkautoAlbumName];
    } error:&creationError];

    if (creationError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to create album: %@\r\n", creationError.localizedDescription]}];
        }
        return nil;
    }

    album = [self fetchTLinkautoAlbum];
    if (!album && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to fetch created album.\r\n"}];
    }
    return album;
}

+ (void)saveToSystemAlbum:(NSString*)filePath error:(NSError**)error
{
    UIImage *image = [UIImage imageWithContentsOfFile:filePath];
    if (!image)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image not found at path.\r\n"}];
        }
        return;
    }

    PHAssetCollection *album = [self ensureTLinkautoAlbumWithError:error];
    if (!album)
    {
        return;
    }

    NSError *saveError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        [albumRequest addAssets:@[[assetRequest placeholderForCreatedAsset]]];
    } error:&saveError];

    if (saveError && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to save to album: %@\r\n", saveError.localizedDescription]}];
    }
}

+ (void)clearSystemAlbum:(NSError**)error
{
    PHAssetCollection *album = [self fetchTLinkautoAlbum];
    if (!album)
    {
        return;
    }

    PHFetchResult<PHAsset*> *assets = [PHAsset fetchAssetsInAssetCollection:album options:nil];
    if (assets.count == 0)
    {
        return;
    }

    NSError *deleteError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } error:&deleteError];

    if (deleteError && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to clear album: %@\r\n", deleteError.localizedDescription]}];
    }
}
