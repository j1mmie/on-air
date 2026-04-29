import wifi
from display import Display
from server import make_server
from state import State
from network import NetworkManager

display = Display()
state = State()

class DisplayStatus:
    def on_connecting(self):      display.connecting()
    def on_connected(self):       pass  # server_ready() called after server setup
    def on_disconnected(self):    display.show_error()
    def start_countdown(self, d): display.start_countdown(d)
    def tick(self):               display.tick()

def on_connected(pool):
    try:
        server = make_server(pool, state, display)
        server.start(str(wifi.radio.ipv4_address))
        print(f"Listening on http://{wifi.radio.ipv4_address}/")
        display.server_ready()
    except Exception as e:
        print(f"Server error: {e}")
        return

    while wifi.radio.connected:
        try:
            server.poll()
        except Exception as e:
            if not wifi.radio.connected:
                break

        expired = state.tick()
        if expired:
            for name in expired:
                print(f"TIMEOUT: {name} | active={state.active()}")
            display.refresh(state.is_on_air(), state.active())

        display.tick()

    print("WiFi lost")
    state.clear()

NetworkManager(DisplayStatus()).run(on_connected)
