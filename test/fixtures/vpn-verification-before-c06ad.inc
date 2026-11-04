static NSDictionary *TLinkVPNPrivateConfigureLegacySync(
    NSString *protocolType,
    NSString *server,
    NSString *user,
    NSString *password,
    NSString *sharedSecret,
    NSString *groupName,
    NSString *displayName,
    NSInteger encryptionLevel,
    BOOL sendAllTraffic)
{
    NSString *failure = nil;
    id store = TLinkVPNPrivateStore(&failure);
    if (!store) return TLinkVPNResult(false,
        failure ?: @"vpn_private_store_unavailable",
        @{@"private_backend_available": @0});

    SEL createSelector = NSSelectorFromString(@"createVPNWithOptions:");
    Class storeClass = [store class];
    BOOL modernStore = [storeClass respondsToSelector:NSSelectorFromString(
        @"createAllVPNByUserDefinedNamesDictionary")];
    BOOL canList =
        [store respondsToSelector:NSSelectorFromString(@"configurations")] ||
        modernStore;
    if (![store respondsToSelector:createSelector] || !canList) {
        return TLinkVPNResult(false,
            @"vpn_private_required_selectors_missing",
            @{@"private_backend_available": @0});
    }

    NSDictionary *oldMarker = TLinkVPNPrivateLoadMarker();
    NSArray<NSDictionary *> *beforeRecords =
        TLinkVPNPrivateConfigurationRecords(store);
    NSMutableSet<NSString *> *beforeIdentifiers = [NSMutableSet set];
    for (NSDictionary *record in beforeRecords) {
        NSString *identifier = record[@"identifier"];
        if (identifier.length > 0) [beforeIdentifiers addObject:identifier];
    }
    NSString *requestedName = [displayName
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (requestedName.length > 48) {
        requestedName = [requestedName substringToIndex:48];
    }
    NSString *nameComponent = requestedName.length > 0
        ? requestedName : protocolType;
    NSString *profileName = [kTLinkVPNPrivateNamePrefix
        stringByAppendingFormat:@"%@ %@", nameComponent,
            [[NSUUID UUID] UUIDString]];
    NSDictionary<NSString *, NSNumber *> *legacyTypeValues = @{
        @"L2TP": @0,
        @"PPTP": @1,
        @"IPSec": @2,
    };
    NSNumber *legacyType = legacyTypeValues[protocolType];
    if (!legacyType) {
        return TLinkVPNResult(false,
            @"vpn_private_protocol_unsupported", @{
                @"profile_type": protocolType ?: @"",
                @"supported_types": @[@"PPTP", @"L2TP", @"IPSec"],
            });
    }
    NSMutableDictionary *options = [@{
        // Mirror XXTouch's documented vpnconf.create contract. The current
        // store consumes the public string; old stores consume its numeric
        // compatibility value. IKEv2 is intentionally excluded here.
        @"VPNType": modernStore ? protocolType : legacyType,
        @"dispName": profileName,
        @"server": server,
        @"authorization": user,
        @"password": password,
        @"authType": [protocolType isEqualToString:@"PPTP"] ? @0 : @1,
        @"encrypLevel": @(MIN(MAX(encryptionLevel, 0), 2)),
        @"VPNSendAllTraffic": @(sendAllTraffic),
        @"group": groupName ?: @"",
        @"secret": sharedSecret ?: @"",
        @"securID": @0,
    } mutableCopy];
    if (!modernStore) {
        // Match the compatibility defaults used by XXTouch only on older
        // VPNConnectionStore implementations.
        options[@"VPNGrade"] = @0;
        options[@"VPNLocalIdentifier"] = @"";
        options[@"VPNRemoteIdentifier"] = @"";
        options[@"VPNRemotedentifier"] = @"";
        options[@"eapType"] = @1;
    }
    uintptr_t created = ((uintptr_t (*)(id, SEL, id))objc_msgSend)(
        store, createSelector, options);
    if (created == 0) {
        return TLinkVPNResult(false, @"vpn_private_create_failed",
            @{@"private_backend_available": @1});
    }

    NSDictionary *newRecord = nil;
    NSString *verificationMode = @"none";
    NSUInteger verificationAttempts = 0;
    NSUInteger observedRecordCount = beforeRecords.count;
    const NSUInteger maximumVerificationAttempts = 50;
    TLinkVPNPrivatePolling::Window verificationWindow(TLinkHelperIO::nowMs(), 5.0);
    for (NSUInteger attempt = 0;
         attempt < maximumVerificationAttempts && !newRecord &&
             verificationWindow.remaining(TLinkHelperIO::nowMs());
         attempt++) {
        verificationAttempts = attempt + 1;
        @autoreleasepool {
            NSArray<NSDictionary *> *afterRecords =
                TLinkVPNPrivateConfigurationRecords(store);
            observedRecordCount = afterRecords.count;

            for (NSDictionary *record in afterRecords) {
                if ([record[@"name"] isEqualToString:profileName]) {
                    newRecord = record;
                    verificationMode = @"exact_name";
                    break;
                }
            }
            if (!newRecord) {
                NSDictionary *deltaRecord = nil;
                NSUInteger deltaCount = 0;
                for (NSDictionary *record in afterRecords) {
                    NSString *identifier = record[@"identifier"];
                    if (identifier.length > 0 &&
                        ![beforeIdentifiers containsObject:identifier]) {
                        if (deltaCount == 0) deltaRecord = record;
                        ++deltaCount;
                    }
                }
                // Retain the sole candidate without materializing a delta array.
                // Ambiguous/new duplicate entries still cannot establish ownership.
                if (deltaCount == 1) {
                    newRecord = deltaRecord;
                    verificationMode = @"single_identifier_delta";
                }
            }
        }
        if (!verificationWindow.remaining(TLinkHelperIO::nowMs())) {
            newRecord = nil;
            verificationMode = @"none";
            break;
        }
        if (!newRecord && attempt + 1 < maximumVerificationAttempts &&
            !TLinkVPNPrivateWaitForVerification(verificationWindow)) {
            break;
        }
    }
    if (!newRecord) {
        return TLinkVPNResult(false,
            @"vpn_private_create_verification_failed",
            @{
                @"private_backend_available": @1,
                @"verification_attempts": @(verificationAttempts),
                @"profiles_before": @(beforeRecords.count),
                @"profiles_observed": @(observedRecordCount),
                @"native_error": @"create returned success but no unique new VPN service became visible",
            });
    }
    // XXTouch treats create + setActiveVPNID as the successful bootstrap.
    // currentConnection may be published asynchronously and is validated when
    // Connect is requested, so do not delete a valid new profile merely
    // because that object is not visible in this same run-loop turn.
    if (!TLinkVPNPrivateSelectConfiguration(store, newRecord)) {
        TLinkVPNPrivateDeleteConfiguration(store, newRecord);
        return TLinkVPNResult(false,
            @"vpn_private_select_verification_failed",
            @{@"private_backend_available": @1});
    }
    if (!TLinkVPNPrivateWriteMarker(
            newRecord, protocolType, &failure)) {
        TLinkVPNPrivateDeleteConfiguration(store, newRecord);
        return TLinkVPNResult(false,
            failure ?: @"vpn_private_marker_write_failed",
            @{@"private_backend_available": @1});
    }

    BOOL oldProfileRemoved = NO;
    if (oldMarker &&
        ![oldMarker[@"identifier"] isEqualToString:newRecord[@"identifier"]]) {
        NSDictionary *oldRecord = TLinkVPNPrivateFindConfiguration(
            store, oldMarker[@"name"], oldMarker[@"identifier"]);
        if (oldRecord &&
            [oldRecord[@"name"] hasPrefix:kTLinkVPNPrivateNamePrefix]) {
            oldProfileRemoved =
                TLinkVPNPrivateDeleteConfiguration(store, oldRecord);
        }
    }
    NSMutableDictionary *fields = [TLinkVPNPrivateStatusFields(
        @{ @"name": newRecord[@"name"],
           @"identifier": newRecord[@"identifier"],
           @"profile_type": protocolType },
        @"disconnected") mutableCopy];
    fields[@"private_backend_available"] = @1;
    fields[@"verification_mode"] = verificationMode;
    fields[@"verification_attempts"] = @(verificationAttempts);
    fields[@"store_schema"] = modernStore ? @"modern" : @"legacy";
    fields[@"old_owned_profile_removed"] = @(oldProfileRemoved);
    fields[@"mutating_api_exercised"] = @1;
    fields[@"approval_path"] =
        @"privhelper_root_private_store_no_nevpnmanager";
    return TLinkVPNResult(true, @"vpn_private_profile_saved", fields);
}

