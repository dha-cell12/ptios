import re

text = open("pccontrol/jsruntime/ipc/TLinkautoJSIPCConnection.mm").read()
text = text.replace('[_socketPath UTF8String], 0660', '[_socketPath UTF8String], 0777')
text = text.replace('"/var/run/tlinkauto/jsruntime.sock"', '"/var/mobile/Library/TLinkauto/run/jsruntime.sock"')
with open("pccontrol/jsruntime/ipc/TLinkautoJSIPCConnection.mm", "w") as f:
    f.write(text)

text = open("pccontrol/jsruntime/TLinkautoJSTaskService.mm").read()
text = text.replace('"/var/run/tlinkauto/jsruntime.sock"', '"/var/mobile/Library/TLinkauto/run/jsruntime.sock"')
with open("pccontrol/jsruntime/TLinkautoJSTaskService.mm", "w") as f:
    f.write(text)

text = open("pccontrol/jsruntime/ipc/tlinkauto-jsd-main.mm").read()
text = text.replace('"/var/run/tlinkauto/jsruntime.sock"', '"/var/mobile/Library/TLinkauto/run/jsruntime.sock"')
text = text.replace('"/var/run/tlinkauto"', '"/var/mobile/Library/TLinkauto/run"')
with open("pccontrol/jsruntime/ipc/tlinkauto-jsd-main.mm", "w") as f:
    f.write(text)
