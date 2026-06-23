import re

text = open("pccontrol/jsruntime/ipc/tlinkauto-jsd-main.mm").read()
text = text.replace('[_conn start];', '[_conn start];\n    // Wait briefly, then broadcast HELLO to any connected clients\n    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n        [_conn sendMessageWithType:TLJS_MSG_HELLO requestId:0 runId:0 generation:0 timeout:5000 payload:@{}];\n    });')
with open("pccontrol/jsruntime/ipc/tlinkauto-jsd-main.mm", "w") as f:
    f.write(text)
