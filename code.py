import os
import time
import wifi
import socketpool
from display import Display
from server import make_server
from state import State

RETRY_INTERVAL = 60

state = State()
display = Display()

while True:
    display.connecting()

    # WiFi connection phase — retry until connected
    while not wifi.radio.connected:
        display.connecting()
        try:
            print("Connecting to WiFi...")
            wifi.radio.connect(os.getenv("WIFI_SSID"), os.getenv("WIFI_PASSWORD"))
            print(f"Connected! IP: {wifi.radio.ipv4_address}")
        except Exception as e:
            print(f"WiFi error: {e}")
            display.show_error()
            display.start_countdown(RETRY_INTERVAL)
            deadline = time.monotonic() + RETRY_INTERVAL
            while time.monotonic() < deadline:
                display.tick()
                time.sleep(0.05)

    # Server setup phase
    try:
        ip = str(wifi.radio.ipv4_address)
        pool = socketpool.SocketPool(wifi.radio)
        server = make_server(pool, state, display)
        server.start(ip)
        print(f"Listening on http://{ip}/")
        display.server_ready()
    except Exception as e:
        print(f"Server error: {e}")
        display.show_error()
        deadline = time.monotonic() + RETRY_INTERVAL
        while time.monotonic() < deadline:
            display.tick()
            time.sleep(0.05)
        continue

    # Main loop — exit when WiFi is lost
    while wifi.radio.connected:
        try:
            server.poll()
        except Exception as e:
            print(f"Poll error: {e}")
            if not wifi.radio.connected:
                break

        expired = state.tick()
        if expired:
            for name in expired:
                print(f"TIMEOUT: {name} | active={state.active()}")
            display.refresh(state.is_on_air(), state.active())

        display.tick()

    # WiFi was lost — clear state and wait before reconnecting
    print("WiFi lost")
    state.clear()
    display.show_error()
    display.start_countdown(RETRY_INTERVAL)
    deadline = time.monotonic() + RETRY_INTERVAL
    while time.monotonic() < deadline:
        display.tick()
        time.sleep(0.05)
