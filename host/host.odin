// Package host supplies a POSIX terminal lifecycle and poll integration for odintui.
package host

import tui ".."
import "base:intrinsics"
import "core:os"
import "core:sys/posix"

when ODIN_OS != .Linux && ODIN_OS != .Darwin {
	#panic("host supports Linux and macOS")
}

DEFAULT_MODES :: tui.Ansi_Terminal_Modes{.Alt_Screen, .Hide_Cursor, .Mouse, .Bracketed_Paste, .Focus}
SIGNALS :: [6]posix.Signal{.SIGINT, .SIGTERM, .SIGHUP, .SIGQUIT, .SIGPIPE, posix.Signal(posix.SIGWINCH)}
MAX_FDS :: 32

// Only one host may be active in a process: POSIX signal handlers are global.
signal_fd: i32 = -1
signal_number: i32
resized: i32

on_signal :: proc "c" (sig: posix.Signal) {
	if sig == posix.Signal(posix.SIGWINCH) {
		intrinsics.atomic_store(&resized, 1)
	} else {
		intrinsics.atomic_store(&signal_number, i32(sig))
	}
	fd := intrinsics.atomic_load(&signal_fd)
	if fd >= 0 {
		b := byte(1)
		_ = posix.write(posix.FD(fd), &b, 1)
	}
}

Host :: struct {
	saved: posix.termios,
	old: [6]posix.sigaction_t,
	installed: int,
	pipe: [2]posix.FD,
	pipe_open, raw, entered, suspended: bool,
	ansi: tui.Ansi_Backend,
	modes: tui.Ansi_Terminal_Modes,
}

raw_attributes :: proc(saved: posix.termios) -> posix.termios {
	raw := saved
	raw.c_iflag -= {.IGNBRK, .BRKINT, .ICRNL, .INLCR, .IGNCR, .INPCK, .ISTRIP, .IXON, .IXOFF, .IXANY, .PARMRK}
	raw.c_oflag -= {.OPOST}
	raw.c_cflag -= posix.CSIZE + {.PARENB}
	raw.c_cflag += transmute(posix.CControl_Flags)posix.tcflag_t(posix.CS8)
	raw.c_lflag -= {.ECHO, .ECHONL, .ICANON, .ISIG, .IEXTEN}
	raw.c_cc[.VMIN] = 1
	raw.c_cc[.VTIME] = 0
	return raw
}

set_attributes :: proc(attributes: ^posix.termios) -> bool {
	for posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, attributes) != .OK {
		if posix.errno() != .EINTR { return false }
	}
	return true
}

// open acquires stdin/stdout, installs handlers and enters the selected modes.
// Always call close, including after a failed open, to unwind partial setup.
open :: proc(h: ^Host, modes := DEFAULT_MODES) -> bool {
	if !posix.isatty(posix.STDIN_FILENO) || !posix.isatty(posix.STDOUT_FILENO) || intrinsics.atomic_load(&signal_fd) >= 0 { return false }
	if posix.tcgetattr(posix.STDIN_FILENO, &h.saved) != .OK { return false }
	if posix.pipe(&h.pipe) != .OK { return false }
	h.pipe_open = true
	for fd in h.pipe {
		flags := posix.fcntl(fd, .GETFL)
		if flags < 0 || posix.fcntl(fd, .SETFL, flags | posix.O_NONBLOCK) < 0 { return false }
		if posix.fcntl(fd, .SETFD, 1) < 0 { return false }
	}
	intrinsics.atomic_store(&signal_number, 0)
	intrinsics.atomic_store(&resized, 0)
	intrinsics.atomic_store(&signal_fd, i32(h.pipe[1]))
	action := posix.sigaction_t{sa_handler = on_signal}
	if posix.sigemptyset(&action.sa_mask) != 0 { return false }
	for sig, i in SIGNALS {
		if posix.sigaction(sig, &action, &h.old[i]) != .OK { return false }
		h.installed += 1
	}
	raw := raw_attributes(h.saved)
	if !set_attributes(&raw) { return false }
	h.raw = true
	h.ansi.writer = os.to_writer(os.stdout)
	h.modes = modes
	h.entered = true // a failed write may have partially entered
	return tui.ansi_enter(&h.ansi, modes)
}

// close restores terminal attributes, modes and previous handlers. Idempotent.
close :: proc(h: ^Host) {
	if h.entered { _ = tui.ansi_leave(&h.ansi, h.modes) }
	if h.raw { _ = set_attributes(&h.saved) }
	signals := SIGNALS
	for i := h.installed-1; i >= 0; i -= 1 { _ = posix.sigaction(signals[i], &h.old[i], nil) }
	if h.pipe_open {
		intrinsics.atomic_store(&signal_fd, -1)
		_ = posix.close(h.pipe[0])
		_ = posix.close(h.pipe[1])
	}
	h^ = {}
}

// suspend leaves the UI modes while preserving raw input for pass-through.
suspend :: proc(h: ^Host) -> bool {
	if !h.entered || h.suspended { return false }
	ok := tui.ansi_leave(&h.ansi, h.modes)
	h.entered = false
	h.suspended = true
	return ok
}

// resume re-enters modes and invalidates the borrowed grid after external output.
resume :: proc(h: ^Host, grid: ^tui.Grid) -> bool {
	if !h.suspended { return false }
	h.entered = true
	h.suspended = false
	ok := tui.ansi_enter(&h.ansi, h.modes)
	if grid != nil { tui.invalidate(grid) }
	return ok
}

Terminal_Size :: struct { rows, columns, x_pixels, y_pixels: u16 }

size :: proc() -> (width, height: int) {
	s := query_size()
	if s.columns == 0 || s.rows == 0 { return 80, 24 }
	return int(s.columns), int(s.rows)
}

// poll waits for stdin and caller descriptors, or timeout_ms (-1 means forever).
// The caller passes pollfd entries and receives their revents in place.
// Signal handlers only set atomics and write to a nonblocking self-pipe;
// restoration is performed by close on the ordinary application thread.
Poll_Result :: struct { input: posix.Poll_Event, signal: i32, resized: bool, timed_out: bool, error: bool }

poll :: proc(h: ^Host, fds: []posix.pollfd, timeout_ms: i32) -> Poll_Result {
	result: Poll_Result
	if !h.pipe_open || len(fds) > MAX_FDS { result.error = true; return result }
	all: [MAX_FDS+2]posix.pollfd
	all[0] = {fd = posix.STDIN_FILENO, events = {.IN}}
	all[1] = {fd = h.pipe[0], events = {.IN}}
	copy(all[2:], fds)
	for i in 0..<len(fds) { all[i+2].revents = {} }
	n := posix.poll(raw_data(all[:]), posix.nfds_t(len(fds)+2), timeout_ms)
	if n < 0 && posix.errno() != .EINTR { result.error = true }
	result.timed_out = n == 0
	result.input = all[0].revents
	for i in 0..<len(fds) { fds[i].revents = all[i+2].revents }
	if .IN in all[1].revents {
		buf: [128]byte
		for posix.read(h.pipe[0], raw_data(buf[:]), len(buf)) > 0 {}
	}
	result.signal = intrinsics.atomic_load(&signal_number)
	result.resized = intrinsics.atomic_exchange(&resized, 0) != 0
	return result
}
