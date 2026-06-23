import re

text = open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm").read()

replacements = {
    "return [self runTask:TASK_PROCESS_BRING_FOREGROUND_URL payload:dict[@\"url\"]];": """return [self runTask:TASK_OPEN_URL payload:dict[@"url"]];""",
    "return [self runTask:TASK_SCREENSHOT_TO payload:dict[@\"path\"]];": """return [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@", dict[@"path"]]];""",
    "return [self runTask:TASK_SCREENSHOT_REGION payload:dict[@\"stringPayload\"]];": """return [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@", dict[@"stringPayload"]]];""",
    "return [self runTask:TASK_SCREENSHOT_SAVE_TO_ALBUM payload:dict[@\"path\"]];": """return [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"2;;%@", dict[@"path"]]];""",
    "return [self runTask:TASK_SCREENSHOT_CLEAR_ALBUM payload:@\"\"];": """return [self runTask:TASK_SCREENSHOT payload:@"3"];""",
    "return [self runTask:TASK_HARDWARE_KEY_PRESS payload:dict[@\"key\"]];": """return [self runTask:TASK_HARDWARE_KEY payload:dict[@"key"]];""",
    "return [self runTask:TASK_SHELL_COMMAND payload:dict[@\"command\"]];": """return [self runTask:TASK_RUN_SHELL payload:dict[@"command"]];""",
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm", "w") as f:
    f.write(text)
