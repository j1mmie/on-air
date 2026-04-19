import time

TIMEOUT = 120  # seconds


class Checkin:
    def __init__(self, name: str):
        self.name = name
        self.checkin_time = time.monotonic()

    def renew(self) -> None:
        self.checkin_time = time.monotonic()

    def is_expired(self) -> bool:
        return time.monotonic() - self.checkin_time > TIMEOUT


class State:
    def __init__(self):
        self._people = []  # [Checkin, ...]

    def add(self, name: str) -> bool:
        """Record or renew name. Returns True if new, False if renewing."""
        for checkin in self._people:
            if checkin.name == name:
                checkin.renew()
                return False
        self._people.append(Checkin(name))
        return True

    def remove(self, name: str) -> None:
        self._people = [c for c in self._people if c.name != name]

    def is_on_air(self) -> bool:
        return bool(self._people)

    def active(self) -> list:
        return [c.name for c in self._people]

    def tick(self) -> list:
        """Remove expired checkins and return their names."""
        expired = [c for c in self._people if c.is_expired()]
        self._people = [c for c in self._people if not c.is_expired()]
        return [c.name for c in expired]
