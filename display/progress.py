import time
import math
import displayio

_SPINNER_INTERVAL = 0.4
_MAX_DOTS = 10


class ProgressBar:
    def __init__(self, group):
        self._group = group

        self._bitmap = displayio.Bitmap(_MAX_DOTS, 1, 2)
        self._palette = displayio.Palette(2)
        self._palette[0] = 0x000000
        self._palette[1] = 0xFFFFFF
        self._palette.make_transparent(0)
        self._tile = displayio.TileGrid(
            self._bitmap,
            pixel_shader=self._palette,
            x=4,
            y=2,
        )

        self._in_group = False
        self._mode = None
        self._spinner_index = 1
        self._last_tick = 0.0
        self._countdown_start = 0.0
        self._countdown_duration = 1.0
        self._last_dots = -1

    def _set_dots(self, count):
        for i in range(_MAX_DOTS):
            self._bitmap[i, 0] = 1 if i < count else 0

    def _attach(self, count):
        self._set_dots(count)
        if not self._in_group:
            self._group.append(self._tile)
            self._in_group = True

    def stop(self):
        if self._in_group:
            self._group.remove(self._tile)
            self._in_group = False
        self._mode = None

    def start_spinner(self):
        self._mode = "spinner"
        self._spinner_index = 1
        self._last_tick = time.monotonic()
        self._attach(1)

    def start_countdown(self, duration):
        self._mode = "countdown"
        self._countdown_start = time.monotonic()
        self._countdown_duration = float(duration)
        self._last_dots = 10
        self._attach(10)

    def tick(self):
        """Returns True if the display needs to be refreshed."""
        if self._mode == "spinner":
            now = time.monotonic()
            if now - self._last_tick >= _SPINNER_INTERVAL:
                self._last_tick = now
                self._spinner_index = self._spinner_index % 3 + 1  # cycles 1 → 2 → 3 → 1
                self._set_dots(self._spinner_index)
                return True
        elif self._mode == "countdown":
            now = time.monotonic()
            elapsed = now - self._countdown_start
            fraction = max(0.0, 1.0 - elapsed / self._countdown_duration)
            dots = math.ceil(fraction * 10)
            if dots != self._last_dots:
                self._last_dots = dots
                self._set_dots(dots)
                return True
        return False
