from adafruit_httpserver import Server, Request, Response


def make_server(pool, state, display) -> Server:
    server = Server(pool, debug=True)

    @server.route("/on")
    def on_handler(request: Request):
        name = (request.query_params.get("name") or "").strip()
        if not name:
            return Response(request, "Missing ?name=\n")
        is_new = state.add(name)
        display.refresh(True, state.active())
        label = "ON    " if is_new else "ON(renew)"
        print(f"{label}: {name} | active={state.active()}")
        return Response(request, f"{name} is ON AIR\n")

    @server.route("/off")
    def off_handler(request: Request):
        name = (request.query_params.get("name") or "").strip()
        if not name:
            return Response(request, "Missing ?name=\n")
        state.remove(name)
        display.refresh(state.is_on_air(), state.active())
        print(f"OFF   : {name} | active={state.active()}")
        return Response(request, f"{name} is OFF AIR\n")

    return server
