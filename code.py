import os
import wifi
import socketpool
from display import Display
from server import make_server

people = {}

display = Display()
display.refresh(False)

print("Connecting to WiFi...")
wifi.radio.connect(os.getenv("WIFI_SSID"), os.getenv("WIFI_PASSWORD"))
ip = str(wifi.radio.ipv4_address)
print(f"Connected! IP: {ip}")

pool = socketpool.SocketPool(wifi.radio)
server = make_server(pool, people, display)
print(f"Listening on http://{ip}/")
server.start(ip)

while True:
    try:
        server.poll()
    except Exception as e:
        print(f"Server error: {e}")
