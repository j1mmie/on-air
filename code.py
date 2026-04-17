import time
import terminalio
from adafruit_matrixportal.matrixportal import MatrixPortal

import os
import ipaddress
import ssl
import wifi
import socketpool
import adafruit_requests

SCROLL_DELAY = 0.03

matrixportal = MatrixPortal(width=64, height=32, bit_depth=6, debug=True)

# Index 0: status line (static)
matrixportal.add_text(
    text_font=terminalio.FONT,
    text_position=(0, 4),
    scrolling=False,
)

# Index 1: quote (scrolling)
matrixportal.add_text(
    text_font=terminalio.FONT,
    text_position=(0, 16),
    scrolling=True,
)

def set_status(msg):
    print(msg)
    matrixportal.set_text(msg, 0)

def show_quote(text):
    print(text)
    matrixportal.set_text(text, 1)
    matrixportal.scroll_text(SCROLL_DELAY)  # blocks until scroll completes

JSON_QUOTES_URL = "https://www.adafruit.com/api/quotes.php"

set_status("Connecting...")
wifi.radio.connect(os.getenv("CIRCUITPY_WIFI_SSID"), os.getenv("CIRCUITPY_WIFI_PASSWORD"))
set_status(f"IP:{wifi.radio.ipv4_address}")
time.sleep(1)

set_status("Pinging...")
ping_ip = ipaddress.IPv4Address("8.8.8.8")
ping = wifi.radio.ping(ip=ping_ip)
if ping is None:
    ping = wifi.radio.ping(ip=ping_ip)

if ping is None:
    set_status("Ping failed")
else:
    set_status(f"Ping:{int(ping*1000)}ms")

time.sleep(1)

pool = socketpool.SocketPool(wifi.radio)
requests = adafruit_requests.Session(pool, ssl.create_default_context())

while True:
    set_status("Fetching quote...")
    response = requests.get(JSON_QUOTES_URL)
    quote_data = response.json()
    quote = quote_data[0].get("text", "No quote")
    author = quote_data[0].get("author", "Unknown")

    set_status("")
    show_quote(f"{quote} -{author}")
    time.sleep(5)
