# Concurrent daemon requests

`dm-compiled [PORT [CACHE_DIRECTORY]]` runs two compiler workers by default.
Set `DM_DAEMON_WORKERS` to `1`, `2`, `3`, or `4` before starting it. One worker
is useful on machines with limited memory. This does not change the wire protocol.

Each worker owns a separate coordinator and its Salsa databases on a thread
with a 16 MiB stack. Compiler databases never move between threads. New worktrees
are assigned to workers in round-robin order; every later request for that
canonical worktree returns to the same worker. This preserves its warm inputs
and serializes builds or patches from that worktree. Two worktrees can compile
at the same time. Several projects in one worktree intentionally share a queue.

All workers use the same immutable disk cache directory. The default directory
is under the Git common directory, so worktrees share persisted results and
ordinary compiler invocations can reuse them after daemon restarts. Each worker
still applies the coordinator's session/input eviction limits independently.

The existing Windows process memory budget covers **all workers together**.
`DM_MEMORY_LIMIT_MB` defaults to 2048; increasing the worker count does not
multiply that ceiling. A large concurrent build may exceed the shared ceiling,
so use one worker for projects that nearly fill it. The host limit is enforced
on Windows; other platforms currently require an external process limit.

Each worker admits two queued requests in addition to its running request.
A full queue returns a structured failure (`compiler queue is full; retry later`)
instead of allocating unbounded pending compiler state. Clients should retry
with backoff. A busy worktree is never moved to another worker to evade its
queue, because that would lose warm state and allow conflicting patches.
The transport tracks at most 1024 worktrees per daemon lifetime; restart the
daemon to admit another worktree after that limit. Disk caches survive.

Request ingestion is limited to 32 MiB and a 15-second read timeout. Compilation
and response delivery occur on workers; a client that stalls while sending its
request can delay admission of other clients until that timeout. `ping` is
answered by the transport without waiting for compiler queues once admitted.
Worker panics return a failure and reset that worker's in-memory compiler state.

Transport tests verify simultaneous execution for two worktrees, stable routing,
bounded overload rejection, and real compiler checks in separate worktrees.
They use small source fixtures and do not launch DreamDaemon.
