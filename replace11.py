import re

text = open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm").read()

replacements = {
    """    __block NSString *responseString = nil;

    dispatch_async(dispatch_get_main_queue(), ^{""": """    __block NSString *responseString = nil;

    dispatch_async(dispatch_get_main_queue(), ^{""",

    """    NSCondition *sleepCondition = exec.sleepCondition;""": """    NSCondition *sleepCondition = [[NSCondition alloc] init];""",

    """    [sleepCondition lock];
    while (!responseString && ![exec isAborted]) {
        [sleepCondition wait];
    }
    [sleepCondition unlock];

    if ([exec isAborted]) {""": """    [sleepCondition lock];
    while (!responseString) {
        [sleepCondition wait];
    }
    [sleepCondition unlock];

    if (!responseString) {"""
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm", "w") as f:
    f.write(text)
