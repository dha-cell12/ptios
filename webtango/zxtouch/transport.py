import json
import socket
import struct


_MAGIC = b"ZXTP"
_VERSION = 1
_HEADER_STRUCT = struct.Struct(">4sBBI")  # magic, version, flags, length
_MAX_BODY = 1024 * 1024


class ZXTouchTransport:
    def __init__(self, sock: socket.socket, protocol: str):
        self._sock = sock
        self._protocol = protocol  # "v0" or "v1"
        self._next_id = 1
        self._v0_buf = bytearray()

    @classmethod
    def connect(cls, ip: str, port: int = 6000, probe_timeout: float = 0.5):
        # First try v1.
        sock = socket.socket()
        sock.connect((str(ip), port))

        try:
            sock.settimeout(probe_timeout)
            self = cls(sock, "v1")
            # Probe with a harmless command: TASK_CURRENT_DIR (45)
            self._send_v1_request(task=45, args=[])
            _ = self._recv_v1_response()
            sock.settimeout(None)
            return self
        except Exception:
            try:
                sock.close()
            except Exception:
                pass

        # Fallback to legacy v0.
        sock = socket.socket()
        sock.connect((str(ip), port))
        return cls(sock, "v0")

    def close(self):
        return self._sock.close()

    def send(self, data: bytes):
        if self._protocol == "v0":
            return self._sock.send(data)

        # data is legacy request bytes: "21/path;;4;;0.8\r\n"
        text = data.decode(errors="strict")
        text = text.replace("\r\n", "")
        if len(text) < 2 or not text[0].isdigit() or not text[1].isdigit():
            raise RuntimeError("Invalid legacy request payload")
        task = int(text[:2])
        rest = text[2:]
        args = []
        if rest:
            args = rest.split(";;")
        self._send_v1_request(task=task, args=args)
        return len(data)

    def recv(self, bufsize: int = 1024):
        if self._protocol == "v0":
            return self._recv_v0_line()

        resp = self._recv_v1_response()
        ok = bool(resp.get("ok"))
        error = resp.get("error")
        data = resp.get("data")

        if not ok:
            msg = str(error or "Unknown error")
            return ("1;;" + msg + "\r\n").encode()

        if data is None:
            return b"0\r\n"

        if not isinstance(data, list):
            data = [data]

        parts = []
        for item in data:
            if isinstance(item, (dict, list)):
                parts.append(json.dumps(item, ensure_ascii=True))
            else:
                parts.append(str(item))

        if not parts:
            return b"0\r\n"
        return ("0;;" + ";;".join(parts) + "\r\n").encode()

    def _recv_v0_line(self) -> bytes:
        # Legacy protocol is line-delimited, but socket.recv() may return partial
        # data. Always read until a full line is available.
        while True:
            nl = self._v0_buf.find(b"\n")
            if nl != -1:
                line = bytes(self._v0_buf[: nl + 1])
                del self._v0_buf[: nl + 1]
                return line

            chunk = self._sock.recv(4096)
            if not chunk:
                raise ConnectionError("Socket closed")
            self._v0_buf.extend(chunk)

    def _send_v1_request(self, task: int, args: list):
        req_id = self._next_id
        self._next_id += 1
        body = json.dumps({"id": req_id, "task": int(task), "args": args}, ensure_ascii=True).encode()
        if len(body) > _MAX_BODY:
            raise RuntimeError("Request too large")
        header = _HEADER_STRUCT.pack(_MAGIC, _VERSION, 0, len(body))
        self._sock.sendall(header + body)

    def _recv_exact(self, n: int) -> bytes:
        out = bytearray()
        while len(out) < n:
            chunk = self._sock.recv(n - len(out))
            if not chunk:
                raise ConnectionError("Socket closed")
            out.extend(chunk)
        return bytes(out)

    def _recv_v1_response(self) -> dict:
        header = self._recv_exact(_HEADER_STRUCT.size)
        magic, ver, _flags, length = _HEADER_STRUCT.unpack(header)
        if magic != _MAGIC or ver != _VERSION:
            raise RuntimeError("Invalid v1 response header")
        if length > _MAX_BODY:
            raise RuntimeError("Response too large")
        body = self._recv_exact(length)
        return json.loads(body.decode())
