# odintui POSIX host

`host.open(&h, modes = host.DEFAULT_MODES) -> bool` acquires stdin/stdout,
enters raw mode and the ANSI modes. Always `defer host.close(&h)` even if
opening fails. One host per process: signal handlers are process-wide.
`host.size() -> (width, height: int)` queries the terminal (80×24 fallback).

`host.poll(&h, fds: []posix.pollfd, timeout_ms: i32) -> Poll_Result` polls
stdin and caller-owned descriptors, returning readiness in `fds[].revents`,
stdin readiness, resize, signal, timeout and error. Use the nearest animation,
escape or other deadline as the timeout. Signal handlers only set atomics and
write a byte to a nonblocking self-pipe; the event loop must notice the signal,
exit and call `close`. SIGKILL and process crashes cannot be handled. Do not
call `os.exit` before closing. `SIGPIPE` is reported like other termination
signals. Linux and macOS are supported.

`host.suspend(&h) -> bool` leaves UI modes while retaining raw pass-through;
`host.resume(&h, &grid) -> bool` re-enters modes and invalidates the grid.
Applications that relay an untrusted program's terminal output must reset
that program's modes before resuming. `h.ansi` is the backend for `tui.render`.
Input parsing is application-owned; see `tui.input_next`.
