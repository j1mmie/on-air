import os
import time
import wifi
import socketpool

RECONNECT_INTERVAL = 60

class NetworkManager:
    def __init__(self, status):
        self._status = status

    def run(self, on_connected):
        while True:
            self._connect()
            pool = socketpool.SocketPool(wifi.radio)
            on_connected(pool)
            self._wait(RECONNECT_INTERVAL)

    def _connect(self):
        self._status.on_connecting()
        while not wifi.radio.connected:
            try:
                wifi.radio.connect(os.getenv("WIFI_SSID"), os.getenv("WIFI_PASSWORD"))
                print(f"Connected! IP: {wifi.radio.ipv4_address}")
            except Exception as e:
                print(f"WiFi error: {e}")
                self._status.on_disconnected()
                self._wait(RECONNECT_INTERVAL)
                self._status.on_connecting()
        self._status.on_connected()

    def _wait(self, duration):
        self._status.start_countdown(duration)
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            self._status.tick()
            time.sleep(0.05)
