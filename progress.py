import time
import math
from adafruit_display_text import label

_SPINNER_FRAMES = [".", "..", "..."]
_SPINNER_INTERVAL = 0.4


class ProgressBar:
    def __init__(self, font, group):
        self._font = font
        self._group = group
        self._label = None
        self._in_group = False
        self._mode = None
        self._spinner_index = 0
        self._last_tick = 0.0
        self._countdown_start = 0.0
        self._countdown_duration = 1.0
        self._last_dots = -1

    def _ensure_label(self):
        if self._label is None:
            self._label = label.Label(
                self._font,
                text=".",
                color=0xFFFFFF,
                anchor_point=(0.5, 0.5),
                anchored_position=(32, 28),
            )

    def _attach(self, text):
        self._ensure_label()
        self._label.text = text
        if not self._in_group:
            self._group.append(self._label)
            self._in_group = True

    def stop(self):
        if self._in_group:
            self._group.remove(self._label)
            self._in_group = False
        self._mode = None

    def start_spinner(self):
        self._mode = "spinner"
        self._spinner_index = 0
        self._last_tick = time.monotonic()
        self._attach(_SPINNER_FRAMES[0])

    def start_countdown(self, duration):
        self._mode = "countdown"
        self._countdown_start = time.monotonic()
        self._countdown_duration = float(duration)
        self._last_dots = 10
        self._attach("." * 10)

    def tick(self):
        """Returns True if the display needs to be refreshed."""
        if self._mode == "spinner":
            now = time.monotonic()
            if now - self._last_tick >= _SPINNER_INTERVAL:
                self._last_tick = now
                self._spinner_index = (self._spinner_index + 1) % len(_SPINNER_FRAMES)
                self._label.text = _SPINNER_FRAMES[self._spinner_index]
                return True
        elif self._mode == "countdown":
            now = time.monotonic()
            elapsed = now - self._countdown_start
            fraction = max(0.0, 1.0 - elapsed / self._countdown_duration)
            dots = math.ceil(fraction * 10)
            if dots != self._last_dots:
                self._last_dots = dots
                self._label.text = "." * dots if dots > 0 else " "
                return True
        return False
