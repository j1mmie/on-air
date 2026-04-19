import os
import wifi
import socketpool
import board
import rgbmatrix
import framebufferio
import displayio
import terminalio
from adafruit_display_text import label
from adafruit_display_shapes.circle import Circle
from adafruit_httpserver import Server, Request, Response

# --- Display ---
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
display = framebufferio.FramebufferDisplay(matrix, auto_refresh=False)

# --- State ---
people = {}  # name -> True when on-air

# --- Display refresh ---
def refresh_display():
    on_air = bool(people)
    group = displayio.Group()

    if on_air:
        # Solid red circle
        circle = Circle(7, 16, 6, fill=0xFF0000)
        text = "On Air"
    else:
        # Gray stroke, black fill
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
    display.root_group = group
    display.refresh()

refresh_display()

# --- WiFi ---
print("Connecting to WiFi...")
wifi.radio.connect(
    os.getenv("CIRCUITPY_WIFI_SSID"),
    os.getenv("CIRCUITPY_WIFI_PASSWORD"),
)
ip = str(wifi.radio.ipv4_address)
print(f"Connected! IP: {ip}")

# --- HTTP server ---
pool = socketpool.SocketPool(wifi.radio)
server = Server(pool, debug=True)

@server.route("/on")
def on_handler(request: Request):
    name = (request.query_params.get("name") or "").strip()
    if not name:
        return Response(request, "Missing ?name=\n")
    people[name] = True
    refresh_display()
    print(f"ON : {name} | active={list(people)}")
    return Response(request, f"{name} is ON AIR\n")

@server.route("/off")
def off_handler(request: Request):
    name = (request.query_params.get("name") or "").strip()
    if not name:
        return Response(request, "Missing ?name=\n")
    people.pop(name, None)
    refresh_display()
    print(f"OFF: {name} | active={list(people)}")
    return Response(request, f"{name} is OFF AIR\n")

print(f"Listening on http://{ip}/")
server.start(ip)

while True:
    try:
        server.poll()
    except Exception as e:
        print(f"Server error: {e}")
