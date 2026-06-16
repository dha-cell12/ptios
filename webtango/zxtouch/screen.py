from zxtouch import tasktypes
from zxtouch import datahandler
from zxtouch import colorsearchtasktypes


class ImageObject:
    def __init__(self, screen, image_id: int, width: int, height: int):
        self._screen = screen
        self.id = int(image_id)
        self.width = int(width)
        self.height = int(height)

    def release(self):
        return self._screen.release_image(self)


class Screen:
    def __init__(self, client):
        self._client = client

    def keep(self):
        """Freeze current screen frame (Screen Keep state)."""
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_SCREEN_KEEP, 1))
        ok, value = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, value
        return True, ""

    def unkeep(self):
        """Exit Screen Keep state."""
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_SCREEN_KEEP, 0))
        ok, value = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, value
        return True, ""

    def is_colors(self, table, mode="similarity", value=0.9):
        """Check multiple absolute points match expected colors.

        Args:
            table: list of (x, y, r, g, b)
            mode: "similarity" or "deviation"
            value: similarity threshold (0..1) or deviation (0..255)
        """
        if not isinstance(table, (list, tuple)) or len(table) == 0:
            raise RuntimeError("table must be a non-empty list")

        mode_code = 0
        if mode == "deviation":
            mode_code = 1
        elif mode != "similarity":
            raise RuntimeError('mode must be "similarity" or "deviation"')

        parts = []
        for p in table:
            if len(p) != 5:
                raise RuntimeError("each point must be (x, y, r, g, b)")
            x, y, r, g, b = p
            parts.append(f"{int(x)},,{int(y)},,{int(r)},,{int(g)},,{int(b)}")
        table_str = "|".join(parts)

        self._client.s.send(
            datahandler.format_socket_data(
                tasktypes.TASK_COLOR_SEARCHER,
                colorsearchtasktypes.SEARCH_MULTI_POINT_IS_COLORS,
                table_str,
                mode_code,
                value,
            )
        )
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res

        matched = False
        if isinstance(res, list) and len(res) >= 1:
            matched = str(res[0]) == "1"
        return True, matched

    def find_color(self, region, table, mode="similarity", value=0.9, pixel_skip=0):
        """Find a multi-point color pattern in a region.

        Args:
            region: (x, y, width, height)
            table: list of (dx, dy, r, g, b) relative to anchor
            mode: "similarity" or "deviation"
            value: similarity threshold (0..1) or deviation (0..255)
            pixel_skip: 0 means check every pixel

        Returns:
            Result tuple. On success, dictionary containing x,y (anchor). If not found, x=y=-1.
        """
        if len(region) != 4:
            raise RuntimeError("region must be (x, y, width, height)")
        if not isinstance(table, (list, tuple)) or len(table) == 0:
            raise RuntimeError("table must be a non-empty list")

        mode_code = 0
        if mode == "deviation":
            mode_code = 1
        elif mode != "similarity":
            raise RuntimeError('mode must be "similarity" or "deviation"')

        parts = []
        for p in table:
            if len(p) != 5:
                raise RuntimeError("each point must be (dx, dy, r, g, b)")
            dx, dy, r, g, b = p
            parts.append(f"{int(dx)},,{int(dy)},,{int(r)},,{int(g)},,{int(b)}")
        table_str = "|".join(parts)

        self._client.s.send(
            datahandler.format_socket_data(
                tasktypes.TASK_COLOR_SEARCHER,
                colorsearchtasktypes.SEARCH_MULTI_POINT_FIND,
                int(region[0]),
                int(region[1]),
                int(region[2]),
                int(region[3]),
                table_str,
                mode_code,
                value,
                int(pixel_skip),
            )
        )
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 2:
            return False, "Invalid find_color response"
        return True, {"x": res[0], "y": res[1]}

    def open_image(self, path: str):
        """Load an image file from device and create an image object."""
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_IMAGE_OBJECT, 2, path))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 3:
            return False, "Invalid open_image response"
        return True, ImageObject(self, int(res[0]), int(res[1]), int(res[2]))

    def image(self, x: int, y: int, width: int, height: int):
        """Capture a screen region and create an image object."""
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_IMAGE_OBJECT, 1, int(x), int(y), int(width), int(height)))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 3:
            return False, "Invalid image() response"
        return True, ImageObject(self, int(res[0]), int(res[1]), int(res[2]))

    def release_image(self, image_obj: ImageObject):
        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_IMAGE_OBJECT, 3, int(image_obj.id)))
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        return True, ""

    def batch_checks_auto_release(self, image_checks=None, color_points=None, coord="pixel", max_age_ms=1000, ttl_ms=1000):
        """Capture one frame, run task70 checks, and release the frame inside task70.

        Args:
            image_checks: list of dicts with template, region, acceptable, scale, pixel_skip.
            color_points: list of (x, y) points for one pick_many op.
            coord: "pixel" or "point".
            max_age_ms: maximum frame age accepted by task70.
            ttl_ms: frame TTL for task66 capture.

        Returns:
            (True, raw_task70_response_list) or (False, error).
        """
        image_checks = image_checks or []
        color_points = color_points or []
        need_gray = 1 if image_checks else 0
        need_bgra = 1 if color_points else 0
        if not need_gray and not need_bgra:
            return False, "image_checks or color_points is required"

        ops = []
        for check in image_checks:
            template = check.get("template") or check.get("image")
            if template is None:
                return False, "image check requires template"
            region = check.get("region", (0, 0, 0, 0))
            if len(region) != 4:
                return False, "image check region must be (x, y, width, height)"
            acceptable = check.get("acceptable", 0.8)
            scale = check.get("scale", 1.0)
            pixel_skip = check.get("pixel_skip", 0)
            ops.append(
                "img,{},{},{},{},{},{},{},{}".format(
                    int(template.id),
                    int(region[0]),
                    int(region[1]),
                    int(region[2]),
                    int(region[3]),
                    float(acceptable),
                    float(scale),
                    int(pixel_skip),
                )
            )

        if color_points:
            points = []
            for point in color_points:
                if len(point) != 2:
                    return False, "color point must be (x, y)"
                points.append(f"{int(point[0])}:{int(point[1])}")
            ops.append("pick_many," + "|".join(points))

        self._client.s.send(datahandler.format_socket_data(tasktypes.TASK_FRAME_CAPTURE, need_gray, need_bgra, int(ttl_ms)))
        ok, frame = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, frame
        if not isinstance(frame, list) or len(frame) < 1:
            return False, "Invalid frame capture response"
        frame_id = frame[0]

        self._client.s.send(
            datahandler.format_socket_data(
                tasktypes.TASK_FRAME_BATCH,
                frame_id,
                "@@".join(ops),
                coord,
                int(max_age_ms),
                1,
            )
        )
        ok, res = datahandler.decode_socket_data(self._client.s.recv(4096))
        if not ok:
            return False, res
        return True, res

    def find_image(self, template: ImageObject, region=(0, 0, 0, 0), acceptable=0.9,
                   scale_min=0.2, scale_max=1.0, scale_step=0.1, pixel_skip=0):
        if len(region) != 4:
            raise RuntimeError("region must be (x, y, width, height)")
        self._client.s.send(
            datahandler.format_socket_data(
                tasktypes.TASK_FIND_IMAGE,
                int(template.id),
                int(region[0]),
                int(region[1]),
                int(region[2]),
                int(region[3]),
                float(acceptable),
                float(scale_min),
                float(scale_max),
                float(scale_step),
                int(pixel_skip),
            )
        )
        ok, res = datahandler.decode_socket_data(self._client.s.recv(1024))
        if not ok:
            return False, res
        if not isinstance(res, list) or len(res) < 7:
            return False, "Invalid find_image response"

        return True, {
            "x": float(res[0]),
            "y": float(res[1]),
            "width": float(res[2]),
            "height": float(res[3]),
            "center_x": float(res[4]),
            "center_y": float(res[5]),
            "score": float(res[6]),
        }

    def wait_find_image(self, template: ImageObject, timeout=5.0, interval=0.2, region=(0, 0, 0, 0),
                        acceptable=0.9, scale_min=0.2, scale_max=1.0, scale_step=0.1, pixel_skip=0):
        """Wait until an image appears on screen.

        Returns:
            (True, match_dict) if found, (True, last_match_dict) if timed out, or (False, error).
            last_match_dict contains best score seen and x/y=-1 if never matched.
        """
        import time

        end = time.time() + float(timeout)
        last = {"x": -1.0, "y": -1.0, "width": 0.0, "height": 0.0, "center_x": -1.0, "center_y": -1.0, "score": 0.0}
        while True:
            ok, err = self.keep()
            if not ok:
                return False, err

            ok, r = self.find_image(
                template,
                region=region,
                acceptable=acceptable,
                scale_min=scale_min,
                scale_max=scale_max,
                scale_step=scale_step,
                pixel_skip=pixel_skip,
            )

            # Always unkeep to allow next iteration to capture a new frame.
            self.unkeep()

            if not ok:
                return False, r

            last = r
            if float(r.get("x", -1)) >= 0:
                return True, r

            if time.time() >= end:
                return True, last

            time.sleep(float(interval))
