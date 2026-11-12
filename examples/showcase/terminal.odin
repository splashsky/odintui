package main

import tui "../.."
import "base:intrinsics"
import "core:os"
import "core:sys/posix"

when ODIN_OS != .Linux && ODIN_OS != .Darwin {
	#panic("showcase supports Linux and macOS")
}

TERMINAL_MODES :: tui.Ansi_Terminal_Modes{
	.Alt_Screen, .Hide_Cursor, .Mouse, .Bracketed_Paste, .Focus,
}

terminal_signal: i32

terminal_on_signal :: proc "c" (signal: posix.Signal) {
	intrinsics.atomic_store(&terminal_signal, i32(signal))
}

Terminal :: struct {
	saved:   posix.termios,
	old:     [5]posix.sigaction_t,
	signals: int,
	raw:     bool,
	entered: bool,
	ansi:    tui.Ansi_Backend,
	parser:  tui.Input_Parser,
	pending: [4096]byte,
	count:   int,
}

TERMINAL_SIGNALS :: [5]posix.Signal{.SIGINT, .SIGTERM, .SIGHUP, .SIGQUIT, .SIGPIPE}

terminal_set_attributes :: proc(attributes: ^posix.termios) -> bool {
	for posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, attributes) != .OK {
		if posix.errno() != .EINTR {
			return false
		}
	}
	return true
}

terminal_open :: proc(term: ^Terminal) -> bool {
	if !posix.isatty(posix.STDIN_FILENO) || !posix.isatty(posix.STDOUT_FILENO) {
		return false
	}
	action := posix.sigaction_t{sa_handler = terminal_on_signal}
	if posix.sigemptyset(&action.sa_mask) != 0 {
		return false
	}
	for signal, i in TERMINAL_SIGNALS {
		if posix.sigaction(signal, &action, &term.old[i]) != .OK {
			return false
		}
		term.signals += 1
	}
	if posix.tcgetattr(posix.STDIN_FILENO, &term.saved) != .OK {
		return false
	}
	raw := term.saved
	raw.c_iflag -= {
		.IGNBRK, .BRKINT, .ICRNL, .INLCR, .IGNCR, .INPCK, .ISTRIP,
		.IXON, .IXOFF, .IXANY, .PARMRK,
	}
	raw.c_oflag -= {.OPOST}
	raw.c_cflag -= posix.CSIZE + {.PARENB}
	raw.c_cflag += {.CS8}
	raw.c_lflag -= {.ECHO, .ECHONL, .ICANON, .ISIG, .IEXTEN}
	raw.c_cc[.VMIN] = 1
	raw.c_cc[.VTIME] = 0
	if !terminal_set_attributes(&raw) {
		return false
	}
	term.raw = true
	term.ansi.writer = os.to_writer(os.stdout)
	// Even a failed enter can have written some mode changes.
	term.entered = true
	return tui.ansi_enter(&term.ansi, TERMINAL_MODES)
}

terminal_close :: proc(term: ^Terminal) {
	if term.entered {
		_ = tui.ansi_leave(&term.ansi, TERMINAL_MODES)
	}
	if term.raw {
		_ = terminal_set_attributes(&term.saved)
	}
	signals := TERMINAL_SIGNALS
	for i := term.signals-1; i >= 0; i -= 1 {
		_ = posix.sigaction(signals[i], &term.old[i], nil)
	}
}

Terminal_Size :: struct {
	rows, columns, x_pixels, y_pixels: u16,
}

terminal_size :: proc() -> (width, height: int) {
	size := terminal_query_size()
	if size.columns == 0 || size.rows == 0 {
		return 80, 24
	}
	return int(size.columns), int(size.rows)
}

// Parsing is synchronous: paste chunks borrow pending only until app_event returns.
terminal_parse :: proc(term: ^Terminal, app: ^App, final: bool) -> bool {
	pending := term.pending[:term.count]
	received := false
	for event in tui.input_next(&term.parser, &pending, final) {
		app_event(app, event)
		received = true
		if app.quit {
			break
		}
	}
	copy(term.pending[:], pending)
	term.count = len(pending)
	return received
}

Poll_Result :: enum {Waiting, Input, Closed, Error}

terminal_poll :: proc(term: ^Terminal, app: ^App) -> Poll_Result {
	timeout := 100
	if term.count > 0 && !term.parser.in_paste {
		timeout = 30
	}
	fd := posix.pollfd{fd = posix.STDIN_FILENO, events = {.IN}}
	ready := posix.poll(&fd, 1, i32(timeout))
	if ready < 0 {
		if posix.errno() == .EINTR {
			return .Waiting
		}
		return .Error
	}
	if ready == 0 {
		if term.count > 0 && !term.parser.in_paste && terminal_parse(term, app, true) {
			return .Input
		}
		return .Waiting
	}
	if .IN in fd.revents {
		if term.count == len(term.pending) {
			if !terminal_parse(term, app, !term.parser.in_paste) {
				return .Error
			}
		}
		n := posix.read(
			posix.STDIN_FILENO, raw_data(term.pending[term.count:]), uint(len(term.pending)-term.count),
		)
		if n < 0 {
			if posix.errno() == .EINTR {
				return .Waiting
			}
			return .Error
		}
		if n == 0 {
			_ = terminal_parse(term, app, true)
			return .Closed
		}
		term.count += int(n)
		if terminal_parse(term, app, false) {
			return .Input
		}
	}
	if .HUP in fd.revents || .ERR in fd.revents || .NVAL in fd.revents {
		_ = terminal_parse(term, app, true)
		return .Closed
	}
	return .Waiting
}
