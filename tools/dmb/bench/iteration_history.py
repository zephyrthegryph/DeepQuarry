"""Independent cumulative source-edit evidence for isolated worktree requests."""
from copy import deepcopy


class EditHistory:
    def __init__(self, sessions):
        if sessions < 1:
            raise ValueError("at least one session is required")
        self._sessions = [[] for _ in range(sessions)]

    def append(self, session, edit):
        self._sessions[session].append(deepcopy(edit))

    def snapshot(self, session):
        return deepcopy(self._sessions[session])
