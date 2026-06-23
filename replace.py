import re
import sys

def replace_stub(match):
    name = match.group(1)
    args = match.group(2)
    stubbed_return = match.group(3)

    return f"- (NSDictionary *){name}:{args} {{\n    return [_execution.taskDispatcher dispatchTask:@\"{name}\" payload:@{{}}];\n}}"

text = open("pccontrol/jsruntime/TLinkautoJSBridge.mm").read()

import fileinput
