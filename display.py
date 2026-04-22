import time
import board
import rgbmatrix
import framebufferio
import displayio
import terminalio
from adafruit_bitmap_font import bitmap_font
from adafruit_display_text import label
from adafruit_display_shapes.circle import Circle
from scroller import Scroller
from progress import ProgressBar

# Green and Blue are swapped on the RGBMatrix
AMBER = 0xFF0080
GREEN = 0x0000FF
RED   = 0xFF0000

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

        self._names_label = label.Label(
            names_font,
            text=" ",
            color=0x404040,
            x=0,
            y=25,
        )

        self._pixel_bmp = displayio.Bitmap(1, 1, 1)
        self._pixel_palette = displayio.Palette(1)
        self._pixel_palette[0] = AMBER
        self._pixel_tile = displayio.TileGrid(self._pixel_bmp, pixel_shader=self._pixel_palette, x=2, y=2)
        self._pixel_in_group = True

        self._circle = None
        self._status_label = None

        self._group = displayio.Group()
        self._group.append(self._names_label)
        self._group.append(self._pixel_tile)
        self._display.root_group = self._group

        self._scroller = Scroller()
        self._scroll_active = False

        self._progress_bar = ProgressBar(self._group)

    def connecting(self) -> None:
        self._pixel_palette[0] = AMBER
        self._progress_bar.stop()
        self.refresh(False, [])

    def start_countdown(self, duration) -> None:
        self._progress_bar.start_countdown(duration)
        self._display.refresh()

    def server_ready(self) -> None:
        self._progress_bar.stop()
        self._pixel_palette[0] = GREEN
        if not self._pixel_in_group:
            self._group.append(self._pixel_tile)
            self._pixel_in_group = True
        self._display.refresh()

    def show_error(self) -> None:
        if self._circle is not None:
            self._group.remove(self._circle)
            self._circle = None
        if self._status_label is not None:
            self._group.remove(self._status_label)
            self._status_label = None
        self._pixel_palette[0] = RED
        if not self._pixel_in_group:
            self._group.append(self._pixel_tile)
            self._pixel_in_group = True
        self._names_label.text = " "
        self._scroll_active = False
        self._display.refresh()

    def refresh(self, is_on_air: bool, names: list) -> None:
        if is_on_air:
            if self._circle is None:
                self._circle = Circle(10, 13, 5, fill=0xFF0000)
                self._group.append(self._circle)
            if self._status_label is None:
                self._status_label = label.Label(
                    terminalio.FONT,
                    text="On Air",
                    color=0xFFFFFF,
                    anchor_point=(0, 0.5),
                    anchored_position=(20, 14),
                )
                self._group.append(self._status_label)
            if self._pixel_in_group:
                self._group.remove(self._pixel_tile)
                self._pixel_in_group = False
        else:
            if self._circle is not None:
                self._group.remove(self._circle)
                self._circle = None
            if self._status_label is not None:
                self._group.remove(self._status_label)
                self._status_label = None
            if not self._pixel_in_group:
                self._group.append(self._pixel_tile)
                self._pixel_in_group = True

        text = ",".join(names)
        self._names_label.text = text or " "
        text_width = self._names_label.bounding_box[2]
        self._scroll_active = bool(text) and text_width > 64
        if self._scroll_active:
            self._names_label.x = self._scroller.reset(text_width)
        else:
            self._names_label.x = (64 - text_width) // 2

        self._display.refresh()

    def tick(self) -> None:
        needs_refresh = False
        if self._scroll_active:
            new_x = self._scroller.tick()
            if new_x is not None:
                self._names_label.x = new_x
                needs_refresh = True
        if self._progress_bar.tick():
            needs_refresh = True
        if needs_refresh:
            self._display.refresh()
