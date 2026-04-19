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
        self._checkins = []  # [Checkin, ...]

    def find(self, name: str):
        for checkin in self._checkins:
            if checkin.name == name:
                return checkin
        return None

    def add(self, name: str) -> bool:
        """Record or renew name. Returns True if new, False if renewing."""
        checkin = self.find(name)
        if checkin:
            checkin.renew()
            return False
        self._checkins.append(Checkin(name))
        return True

    def remove(self, name: str) -> None:
        for i, c in enumerate(self._checkins):
            if c.name == name:
                del self._checkins[i]
                return

    def is_on_air(self) -> bool:
        return bool(self._checkins)

    def active(self) -> list:
        return [c.name for c in self._checkins]

    def tick(self) -> list:
        """Remove expired checkins and return their names."""
        expired = [c for c in self._checkins if c.is_expired()]
        self._checkins = [c for c in self._checkins if not c.is_expired()]
        return [c.name for c in expired]
