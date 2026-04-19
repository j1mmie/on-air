import board
import rgbmatrix
import framebufferio
import displayio
import terminalio
from adafruit_display_text import label
from adafruit_display_shapes.circle import Circle


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

    def refresh(self, is_on_air: bool) -> None:
        group = displayio.Group()

        if is_on_air:
            circle = Circle(7, 16, 6, fill=0xFF0000)
            text = "On Air"
        else:
            circle = Circle(7, 16, 6, fill=0x000000, outline=0x606060, stroke=2)
            text = "Off Air"

        txt = label.Label(
            terminalio.FONT,
            text=text,
            color=0xFFFFFF,
            anchor_point=(0, 0.5),
            anchored_position=(16, 16),
        )

        group.append(circle)
        group.append(txt)
        self._display.root_group = group
        self._display.refresh()
