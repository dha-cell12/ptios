static NSArray<NSDictionary *> *TLinkVPNPrivateConfigurationRecords(id store)
{
    id rawConfigurations = TLinkVPNPrivateSendId(
        store, NSSelectorFromString(@"configurations"));
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    if ([rawConfigurations conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id configuration in rawConfigurations) {
            id rawName = TLinkVPNPrivateSendId(configuration, @selector(name));
            id rawIdentifier = TLinkVPNPrivateSendId(
                configuration, @selector(identifier));
            NSString *name = [rawName isKindOfClass:[NSString class]]
                ? rawName : @"";
            NSString *identifier =
                TLinkVPNPrivateIdentifierString(rawIdentifier);
            if (name.length == 0 || identifier.length == 0) continue;
            [records addObject:@{
                @"name": name,
                @"identifier": identifier,
                @"raw_identifier": rawIdentifier,
            }];
        }
    }
    Class storeClass = [store class];
    id names = TLinkVPNPrivateSendId(
        (id)storeClass,
        NSSelectorFromString(@"createAllVPNByUserDefinedNamesDictionary"));
    if ([names isKindOfClass:[NSDictionary class]]) {
        [(NSDictionary *)names enumerateKeysAndObjectsUsingBlock:
            ^(id rawName, id service, BOOL *stop) {
            (void)stop;
            NSString *name = [rawName isKindOfClass:[NSString class]]
                ? rawName : @"";
            NSString *identifier =
                TLinkVPNPrivateServiceIdentifier(service);
            if (name.length == 0 || identifier.length == 0) return;
            for (NSDictionary *existing in records) {
                if ([existing[@"identifier"] isEqualToString:identifier]) {
                    return;
                }
            }
            [records addObject:@{
                @"name": name,
                @"identifier": identifier,
                @"raw_identifier": identifier,
            }];
        }];
    }
    return records;
}

