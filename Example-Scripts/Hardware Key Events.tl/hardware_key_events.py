from tlinkauto.client import TLinkauto
from tlinkauto.hardwarekeytypes import (
    HARDWARE_KEY_HOME,
    HARDWARE_KEY_VOLUME_UP,
    HARDWARE_KEY_VOLUME_DOWN,
    HARDWARE_KEY_LOCK,
)
from tlinkauto.toasttypes import TOAST_WARNING
import time


def press_key(device, key_type, delay=0.2):
    device.key_down(key_type)
    time.sleep(delay)
    device.key_up(key_type)


def main():
    device = TLinkauto("127.0.0.1")

    device.show_toast(TOAST_WARNING, "Testing hardware key events...", 2)
    time.sleep(2)

    press_key(device, HARDWARE_KEY_VOLUME_UP)
    device.show_toast(TOAST_WARNING, "Volume up pressed", 2)
    time.sleep(1)
    press_key(device, HARDWARE_KEY_VOLUME_DOWN)
    device.show_toast(TOAST_WARNING, "Volume down pressed", 2)
    time.sleep(1)
    press_key(device, HARDWARE_KEY_HOME)
    device.show_toast(TOAST_WARNING, "Home pressed", 2)
    time.sleep(1)
    press_key(device, HARDWARE_KEY_LOCK)
    device.show_toast(TOAST_WARNING, "Lock pressed", 2)

    device.disconnect()


if __name__ == "__main__":
    main()
