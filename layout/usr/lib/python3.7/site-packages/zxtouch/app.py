import base64
import json

from zxtouch import datahandler
from zxtouch import tasktypes


class App:
    def __init__(self, client):
        self._client = client

    def pid_for_bid(self, bundle_id: str):
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_APP_PID, bundle_id))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 1:
            return False, "Invalid pid response"
        try:
            return True, int(res[0])
        except Exception:
            return False, "Invalid pid value"

    def front_pid(self):
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_FRONTMOST_PID))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 1:
            return False, "Invalid front_pid response"
        try:
            return True, int(res[0])
        except Exception:
            return False, "Invalid pid value"

    def bundle_path(self, bundle_id: str):
        ok, paths = self._paths(bundle_id)
        if not ok:
            return False, paths
        return True, paths.get("bundle_path", "")

    def data_path(self, bundle_id: str):
        ok, paths = self._paths(bundle_id)
        if not ok:
            return False, paths
        return True, paths.get("data_path", "")

    def _paths(self, bundle_id: str):
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_APP_PATHS, bundle_id))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(2048))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 2:
            # server returns bundle_path;;data_path
            return False, "Invalid paths response"
        return True, {"bundle_path": res[0], "data_path": res[1]}

    def bundles(self, with_info: bool = True):
        # with_info=1 returns base64(json). with_info=0 returns bid1,,bid2,,...
        flag = 1 if with_info else 0
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_LIST_BUNDLES, flag))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024 * 1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 1:
            return False, "Invalid bundles response"

        if not with_info:
            raw = res[0]
            if not raw:
                return True, []
            return True, [x for x in raw.split(",,") if x]

        b64 = res[0]
        try:
            payload = base64.b64decode(b64.encode("ascii"), validate=False)
            obj = json.loads(payload.decode("utf-8", errors="strict"))
            items = obj.get("items", [])
            if not isinstance(items, list):
                return False, "Invalid bundles JSON"
            return True, items
        except Exception as e:
            return False, "Failed to decode bundles: " + str(e)

    def open_url(self, url: str):
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_OPEN_URL, url))
        return datahandler.decode_socket_data(self._client.s.recv(1024))
