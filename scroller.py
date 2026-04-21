import time

DISPLAY_WIDTH  = 64
SCROLL_DELAY   = 0.04   # seconds per pixel
PAUSE_DURATION = 1.0    # seconds to hold at each end before reversing

_PAUSE_START  = 0
_SCROLL_LEFT  = 1
_PAUSE_END    = 2
_SCROLL_RIGHT = 3


class Scroller:
    def __init__(self):
        self._state = _PAUSE_START
        self._x     = 0
        self._end_x = 0
        self._t     = 0.0

    def reset(self, text_width: int) -> int:
        """Call when text changes. Returns the starting x (always 0)."""
        self._end_x = DISPLAY_WIDTH - text_width  # negative: how far left to scroll
        self._x     = 0
        self._state = _PAUSE_START
        self._t     = time.monotonic()
        return 0

    def tick(self):
        """Return new x if the label position changed, otherwise None."""
        now     = time.monotonic()
        elapsed = now - self._t

        if self._state == _PAUSE_START:
            if elapsed >= PAUSE_DURATION:
                self._state = _SCROLL_LEFT
                self._t     = now

        elif self._state == _SCROLL_LEFT:
            if elapsed >= SCROLL_DELAY:
                self._t  = now
                self._x -= 1
                if self._x <= self._end_x:
                    self._x     = self._end_x
                    self._state = _PAUSE_END
                    self._t     = now
                return self._x

        elif self._state == _PAUSE_END:
            if elapsed >= PAUSE_DURATION:
                self._state = _SCROLL_RIGHT
                self._t     = now

        elif self._state == _SCROLL_RIGHT:
            if elapsed >= SCROLL_DELAY:
                self._t  = now
                self._x += 1
                if self._x >= 0:
                    self._x     = 0
                    self._state = _PAUSE_START
                    self._t     = now
                return self._x

        return None
