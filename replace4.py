import re

text = open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm").read()

mappings = {
    "TASK_SCREENSHOT_TO": "TASK_SCREENSHOT",
    "TASK_SCREENSHOT_REGION": "TASK_SCREENSHOT",
    "TASK_SCREENSHOT_SAVE_TO_ALBUM": "TASK_SCREENSHOT",
    "TASK_SCREENSHOT_CLEAR_ALBUM": "TASK_SCREENSHOT",
    "TASK_PROCESS_BRING_FOREGROUND_URL": "TASK_OPEN_URL",
    "TASK_HARDWARE_KEY_PRESS": "TASK_HARDWARE_KEY",
    "TASK_SHELL_COMMAND": "TASK_RUN_SHELL",
}

for k, v in mappings.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm", "w") as f:
    f.write(text)
