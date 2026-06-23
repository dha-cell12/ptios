import re

text = open("pccontrol/jsruntime/TLinkautoJSTaskService.mm").read()

replacements = {
    """    [_connection sendMessageWithType:TLJS_MSG_START_RUN
                           requestId:0
                               runId:gen
                          generation:gen
                             timeout:5000
                             payload:payload];

    return YES;""": """    [_connection sendMessageWithType:TLJS_MSG_START_RUN
                           requestId:0
                               runId:gen
                          generation:gen
                             timeout:5000
                             payload:payload];

    os_unfair_lock_lock(&_lock);
    _isRunning = YES;
    while (_isRunning) {
        [_runCondition wait];
    }
    BOOL success = _lastRunSuccess;
    if (!success && error) {
        *error = [NSError errorWithDomain:@"TLinkautoJSTaskService" code:1 userInfo:@{NSLocalizedDescriptionKey: _lastRunError ?: @"Script execution failed"}];
    }
    os_unfair_lock_unlock(&_lock);

    return success;""",

    """    BOOL _daemonConnected;""": """    BOOL _daemonConnected;
    BOOL _isRunning;
    BOOL _lastRunSuccess;
    NSString *_lastRunError;
    NSCondition *_runCondition;""",

    """        _connection = [[TLinkautoJSIPCConnection alloc] initWithSocketFile:@"/var/mobile/Library/TLinkauto/run/jsruntime.sock" isServer:NO];
        _connection.delegate = self;""": """        _connection = [[TLinkautoJSIPCConnection alloc] initWithSocketFile:@"/var/mobile/Library/TLinkauto/run/jsruntime.sock" isServer:NO];
        _connection.delegate = self;
        _runCondition = [[NSCondition alloc] init];""",

    """    else if (header.messageType == TLJS_MSG_TASK_REQUEST) {
        [self handleTaskRequest:header payload:payload];
    }""": """    else if (header.messageType == TLJS_MSG_TASK_REQUEST) {
        [self handleTaskRequest:header payload:payload];
    }
    else if (header.messageType == TLJS_MSG_RUN_FINISHED) {
        os_unfair_lock_lock(&_lock);
        _isRunning = NO;
        _lastRunSuccess = [payload[@"ok"] boolValue];
        _lastRunError = payload[@"error"];
        [_runCondition broadcast];
        os_unfair_lock_unlock(&_lock);
    }""",

    """- (void)stopService {
    [_connection stop];
}""": """- (void)stopService {
    [_connection stop];
    os_unfair_lock_lock(&_lock);
    _isRunning = NO;
    [_runCondition broadcast];
    os_unfair_lock_unlock(&_lock);
}""",

    """- (void)connectionDidDisconnect {
    os_unfair_lock_lock(&_lock);
    _daemonConnected = NO;
    os_unfair_lock_unlock(&_lock);
}""": """- (void)connectionDidDisconnect {
    os_unfair_lock_lock(&_lock);
    _daemonConnected = NO;
    _isRunning = NO;
    [_runCondition broadcast];
    os_unfair_lock_unlock(&_lock);
}"""
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSTaskService.mm", "w") as f:
    f.write(text)
