import os
import wifi
import socketpool
from display import Display
from server import make_server
from state import State

state = State()

display = Display()
display.refresh(False, [])

try:
    print("Connecting to WiFi...")
    wifi.radio.connect(os.getenv("WIFI_SSID"), os.getenv("WIFI_PASSWORD"))
    ip = str(wifi.radio.ipv4_address)
    print(f"Connected! IP: {ip}")

    pool = socketpool.SocketPool(wifi.radio)
    server = make_server(pool, state, display)
    server.start(ip)
    print(f"Listening on http://{ip}/")
    display.server_ready()

    while True:
        server.poll()

        expired = state.tick()
        if expired:
            for name in expired:
                print(f"TIMEOUT: {name} | active={state.active()}")
            display.refresh(state.is_on_air(), state.active())

        display.tick()

except Exception as e:
    print(f"FATAL: {e}")
    display.show_error()
    while True:
        pass
