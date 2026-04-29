# circup install neopixel adafruit_requests
import os
import time
import wifi
import board
import digitalio
import neopixel
import adafruit_requests
from network import NetworkManager

pixel = neopixel.NeoPixel(board.NEOPIXEL, 1, brightness=0.2, auto_write=True)

ORANGE  = (255, 100,   0)
GREEN   = (  0, 255,   0)
RED     = (255,   0,   0)
FUCHSIA = (255,   0, 255)

SEND_INTERVAL = 60

class ClickerStatus:
    def on_connecting(self):      pixel[0] = ORANGE
    def on_connected(self):       pixel[0] = GREEN
    def on_disconnected(self):    pixel[0] = RED
    def start_countdown(self, d): pass
    def tick(self):               pass

def on_connected(pool):
    base_url = os.getenv("SERVER_URL")
    name     = os.getenv("CLICKER_NAME")
    session  = adafruit_requests.Session(pool)

    button = digitalio.DigitalInOut(board.D0)
    button.switch_to_input(pull=digitalio.Pull.UP)

    active       = False
    last_send    = 0
    prev_value   = True   # True = not pressed (pull-up, active low)
    debounce_end = 0

    while wifi.radio.connected:
        now       = time.monotonic()
        curr_value = button.value  # False = pressed

        # Detect falling edge after debounce settles
        if not curr_value and prev_value and now >= debounce_end:
            debounce_end = now + 0.05
            if active:
                active = False
                pixel[0] = GREEN
                try:
                    session.get(f"{base_url}/off?name={name}")
                    print(f"OFF: {name}")
                except Exception as e:
                    print(f"Request error: {e}")
            else:
                active    = True
                last_send = now - SEND_INTERVAL  # trigger immediate first send
                pixel[0]  = FUCHSIA

        prev_value = curr_value

        if active and (now - last_send) >= SEND_INTERVAL:
            try:
                session.get(f"{base_url}/on?name={name}")
                print(f"ON: {name}")
                last_send = now
            except Exception as e:
                print(f"Request error: {e}")
                if not wifi.radio.connected:
                    break

        time.sleep(0.01)

NetworkManager(ClickerStatus()).run(on_connected)
