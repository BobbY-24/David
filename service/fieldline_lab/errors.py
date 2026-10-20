class QueueFull(Exception):
    def __init__(self, cap: int, depth: int) -> None:
        self.cap = cap
        self.depth = depth
        super().__init__(f"Queue cap of {cap} is full. {depth} jobs are queued or running.")


class IdempotencyConflict(Exception):
    def __init__(self) -> None:
        super().__init__("This idempotency key was already used for a different request.")


class TransientJobError(Exception):
    """Worker should retry until max_attempts, then mark the job dead."""


class PermanentJobError(Exception):
    """Do not retry. The request itself cannot succeed."""
