import time

TIMEOUT = 120  # seconds


class State:
    def __init__(self):
        self._people = []  # [(name, monotonic timestamp), ...]

    def add(self, name: str) -> bool:
        """Record or renew name. Returns True if new, False if renewing."""
        now = time.monotonic()
        for i, (n, _) in enumerate(self._people):
            if n == name:
                self._people[i] = (name, now)
                return False
        self._people.append((name, now))
        return True

    def remove(self, name: str) -> None:
        self._people = [(n, ts) for n, ts in self._people if n != name]

    def is_on_air(self) -> bool:
        return bool(self._people)

    def active(self) -> list:
        return [n for n, _ in self._people]

    def tick(self) -> list:
        """Remove expired names and return them."""
        now = time.monotonic()
        expired = [n for n, ts in self._people if now - ts > TIMEOUT]
        self._people = [(n, ts) for n, ts in self._people if now - ts <= TIMEOUT]
        return expired
