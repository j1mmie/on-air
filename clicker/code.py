import wifi
import board
import neopixel
from network import NetworkManager

pixel = neopixel.NeoPixel(board.NEOPIXEL, 1, brightness=0.2, auto_write=True)

ORANGE = (255, 100, 0)
GREEN  = (0, 255, 0)
RED    = (255, 0, 0)

class ClickerStatus:
    def on_connecting(self):      pixel[0] = ORANGE
    def on_connected(self):       pixel[0] = GREEN
    def on_disconnected(self):    pixel[0] = RED
    def start_countdown(self, d): pass
    def tick(self):               pass

def on_connected(pool):
    while wifi.radio.connected:
        pass  # button logic goes here

NetworkManager(ClickerStatus()).run(on_connected)
