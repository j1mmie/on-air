import time

TIMEOUT = 120  # seconds


class State:
    def __init__(self):
        self._people = {}  # name -> monotonic timestamp of last check-in

    def add(self, name: str) -> bool:
        """Record or renew name. Returns True if new, False if renewing."""
        is_new = name not in self._people
        self._people[name] = time.monotonic()
        return is_new

    def remove(self, name: str) -> None:
        self._people.pop(name, None)

    def is_on_air(self) -> bool:
        return bool(self._people)

    def active(self) -> list:
        return list(self._people)

    def tick(self) -> list:
        """Remove expired names and return them."""
        now = time.monotonic()
        expired = [n for n, ts in self._people.items() if now - ts > TIMEOUT]
        for name in expired:
            del self._people[name]
        return expired
