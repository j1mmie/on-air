from adafruit_httpserver import Server, Request, Response


def make_server(pool, people: dict, display) -> Server:
    server = Server(pool, debug=True)

    @server.route("/on")
    def on_handler(request: Request):
        name = (request.query_params.get("name") or "").strip()
        if not name:
            return Response(request, "Missing ?name=\n")
        people[name] = True
        display.refresh(True)
        print(f"ON : {name} | active={list(people)}")
        return Response(request, f"{name} is ON AIR\n")

    @server.route("/off")
    def off_handler(request: Request):
        name = (request.query_params.get("name") or "").strip()
        if not name:
            return Response(request, "Missing ?name=\n")
        people.pop(name, None)
        display.refresh(bool(people))
        print(f"OFF: {name} | active={list(people)}")
        return Response(request, f"{name} is OFF AIR\n")

    return server
