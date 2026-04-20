import time
import board
import rgbmatrix
import framebufferio
import displayio
import terminalio
from adafruit_bitmap_font import bitmap_font
from adafruit_display_text import label
from adafruit_display_shapes.circle import Circle

SCROLL_DELAY = 0.04  # seconds per pixel (~25 fps)


class Display:
    def __init__(self):
        displayio.release_displays()
        matrix = rgbmatrix.RGBMatrix(
            width=64, height=32, bit_depth=4,
            rgb_pins=[
                board.MTX_R1, board.MTX_G1, board.MTX_B1,
                board.MTX_R2, board.MTX_G2, board.MTX_B2,
            ],
            addr_pins=[board.MTX_ADDRA, board.MTX_ADDRB, board.MTX_ADDRC, board.MTX_ADDRD],
            clock_pin=board.MTX_CLK,
            latch_pin=board.MTX_LAT,
            output_enable_pin=board.MTX_OE,
        )
        self._display = framebufferio.FramebufferDisplay(matrix, auto_refresh=False)

        names_font = bitmap_font.load_font("/fonts/tom-thumb.bdf")

        self._circle = Circle(7, 13, 6, fill=0x000000, outline=0x606060, stroke=2)
        self._status_label = label.Label(
            terminalio.FONT,
            text="Off Air",
            color=0xFFFFFF,
            anchor_point=(0, 0.5),
            anchored_position=(16, 13),
        )
        self._names_label = label.Label(
            names_font,
            text=" ",
            color=0xAAAAAA,
            x=0,
            y=25,
        )

        self._group = displayio.Group()
        self._group.append(self._circle)
        self._group.append(self._status_label)
        self._group.append(self._names_label)
        self._display.root_group = self._group

        self._scroll_x = 0
        self._text_width = 0
        self._scroll_needed = False
        self._last_scroll_t = 0.0

    def refresh(self, is_on_air: bool, names: list) -> None:
        if is_on_air:
            new_circle = Circle(7, 13, 6, fill=0xFF0000)
            self._status_label.text = "On Air"
        else:
            new_circle = Circle(7, 13, 6, fill=0x000000, outline=0x606060, stroke=2)
            self._status_label.text = "Off Air"
        self._group[0] = new_circle
        self._circle = new_circle

        text = ", ".join(names)
        self._names_label.text = text or " "
        self._names_label.x = 0
        self._scroll_x = 0
        self._text_width = self._names_label.bounding_box[2]
        self._scroll_needed = bool(text) and self._text_width > 64
        self._last_scroll_t = time.monotonic()

        self._display.refresh()

    def tick(self) -> None:
        if not self._scroll_needed:
            return
        now = time.monotonic()
        if now - self._last_scroll_t < SCROLL_DELAY:
            return
        self._last_scroll_t = now
        self._scroll_x -= 1
        if self._scroll_x + self._text_width < 0:
            self._scroll_x = 0
        self._names_label.x = self._scroll_x
        self._display.refresh()
