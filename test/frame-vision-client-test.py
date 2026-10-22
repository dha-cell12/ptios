import json
import pathlib
import struct
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "webtango"))
from tlinkauto.client import TLinkauto
from tlinkauto.transport import TLinkautoTransport

class Socket:
    def __init__(self, response):
        self.pending = bytearray(response)
        self.sent = bytearray()
    def send(self, data):
        self.sent.extend(data)
        return len(data)
    def sendall(self, data):
        self.sent.extend(data)
    def recv(self, count):
        size = min(count, 3, len(self.pending))
        chunk = bytes(self.pending[:size])
        del self.pending[:size]
        return chunk

for protocol in ("v0", "v1"):
    response = b"0;;hello,,22,,30,,25,,20\r\n"
    if protocol == "v1":
        body = json.dumps({"ok": True, "data": ["hello,,22,,30,,25,,20"]}).encode()
        response = struct.pack(">4sBBI", b"ZXTP", 1, 0, len(body)) + body
    socket = Socket(response)
    client = TLinkauto.__new__(TLinkauto)
    client.s = TLinkautoTransport(socket, protocol)
    ok, result = client.ocr_from_frame(7, (10, 20, 50, 40), languages=["en-US"])
    assert ok and result == [{"text": "hello", "x": "22", "y": "30", "width": "25", "height": "20"}]
    sent = bytes(socket.sent)
    if protocol == "v0":
        assert sent == b"276;;10,,20,,50,,40;;;;;;0;;en-US;;0;;;;7;;pixel;;1000\r\n", sent
    else:
        request = json.loads(sent[10:])
        assert request["task"] == 27 and request["args"][0] == "6" and request["args"][-3:] == ["7", "pixel", "1000"]
client.s = TLinkautoTransport(Socket(b"-1;;vision_frame_expired\r\n"), "v0")
assert client.ocr_from_frame(1) == (False, "vision_frame_expired")
client.s = TLinkautoTransport(Socket(b"0;;\r\n"), "v0")
assert client.ocr_from_frame(1) == (True, [])
client.s = TLinkautoTransport(Socket(b"0;;bad,,shape\r\n"), "v0")
assert client.ocr_from_frame(1)[0] is False
for frame_id, age, coord in [(0, 1000, "pixel"), (2147483648, 1000, "pixel"), (True, 1000, "pixel"), (1, 5001, "pixel"), (1, 1000, "bad")]:
    try:
        client.ocr_from_frame(frame_id, max_age_ms=age, coord=coord)
        raise AssertionError("accepted invalid frame arguments")
    except ValueError:
        pass
print("Frame Vision Python client passed: exact v0/v1 payload, fragmented transport, five observation fields, expiry/error and validation.")
