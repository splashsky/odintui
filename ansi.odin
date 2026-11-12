package odintui

import "core:io"

// Ansi_Backend buffers encoded output for writer. Do not copy it or modify
// its internal state while in use; the writer must outlive the backend.
Ansi_Backend :: struct {
	writer:       io.Writer,
	buffer:       [4096]byte,
	buffer_len:   int,
	cursor_x:     int,
	cursor_y:     int,
	cursor_known: bool,
	style:        Style,
	style_known:  bool,
	cancel:       bool,
}

// ansi_backend returns callbacks borrowing state; state must outlive the Backend.
ansi_backend :: proc(state: ^Ansi_Backend) -> Backend {
	return {state, ansi_draw_run, ansi_flush}
}

@(private)
ansi_fail :: proc(state: ^Ansi_Backend) {
	state.buffer_len = 0
	state.cursor_known = false
	state.style_known = false
	state.cancel = true
}

@(private)
ansi_drain :: proc(state: ^Ansi_Backend) -> bool {
	if state.buffer_len == 0 {
		return true
	}
	n, err := io.write(state.writer, state.buffer[:state.buffer_len])
	if err != nil || n != state.buffer_len {
		ansi_fail(state)
		return false
	}
	state.buffer_len = 0
	return true
}

@(private)
ansi_prepare :: proc(state: ^Ansi_Backend) {
	if state.cancel {
		// CAN terminates any escape sequence interrupted by a short write.
		state.buffer[state.buffer_len] = 0x18
		state.buffer_len += 1
		state.cancel = false
	}
}

@(private)
ansi_reserve :: proc(state: ^Ansi_Backend, size: int) -> bool {
	if state.buffer_len+size > len(state.buffer) {
		return ansi_drain(state)
	}
	return true
}

@(private)
ansi_append :: proc(state: ^Ansi_Backend, s: string) {
	copy(state.buffer[state.buffer_len:], transmute([]byte)s)
	state.buffer_len += len(s)
}

@(private)
ansi_number :: proc(state: ^Ansi_Backend, n: u64) {
	digits: [20]byte
	start := len(digits)
	value := n
	for {
		start -= 1
		digits[start] = byte('0') + byte(value % 10)
		value /= 10
		if value == 0 {
			break
		}
	}
	state.buffer_len += copy(state.buffer[state.buffer_len:], digits[start:])
}

@(private)
ansi_move :: proc(state: ^Ansi_Backend, x, y: int) {
	ansi_append(state, "\x1b[")
	ansi_number(state, u64(y)+1)
	ansi_append(state, ";")
	ansi_number(state, u64(x)+1)
	ansi_append(state, "H")
	state.cursor_x, state.cursor_y, state.cursor_known = x, y, true
}

@(private)
ansi_style :: proc(state: ^Ansi_Backend, style: Style) {
	ansi_append(state, "\x1b[0")
	if .Bold in style.attributes {
		ansi_append(state, ";1")
	}
	if .Dim in style.attributes {
		ansi_append(state, ";2")
	}
	if .Italic in style.attributes {
		ansi_append(state, ";3")
	}
	if .Underline in style.attributes {
		ansi_append(state, ";4")
	}
	if .Blink in style.attributes {
		ansi_append(state, ";5")
	}
	if .Reverse in style.attributes {
		ansi_append(state, ";7")
	}
	if .Hidden in style.attributes {
		ansi_append(state, ";8")
	}
	if .Strikethrough in style.attributes {
		ansi_append(state, ";9")
	}
	if style.fg.is_rgb {
		ansi_color(state, style.fg, true)
	}
	if style.bg.is_rgb {
		ansi_color(state, style.bg, false)
	}
	ansi_append(state, "m")
	state.style, state.style_known = style, true
}

@(private)
ansi_color :: proc(state: ^Ansi_Backend, color: Color, foreground: bool) {
	if foreground {
		ansi_append(state, ";38;2;")
	} else {
		ansi_append(state, ";48;2;")
	}
	ansi_number(state, u64(color.r))
	ansi_append(state, ";")
	ansi_number(state, u64(color.g))
	ansi_append(state, ";")
	ansi_number(state, u64(color.b))
}

@(private)
ansi_draw_run :: proc(data: rawptr, x, y: int, cells: []Cell) -> bool {
	state := (^Ansi_Backend)(data)
	if state == nil {
		return false
	}
	if x < 0 || y < 0 || x == max(int) || y == max(int) ||
	   len(cells) > max(int)-x {
		ansi_fail(state)
		return false
	}
	if len(cells) == 0 {
		return true
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 128) {
		return false
	}
	if !state.cursor_known || state.cursor_x != x || state.cursor_y != y {
		ansi_move(state, x, y)
	}
	for cell in cells {
		if !ansi_reserve(state, 128) {
			return false
		}
		if !state.style_known || state.style != cell.style {
			ansi_style(state, cell.style)
		}
		glyph := byte('?')
		if cell.glyph >= ' ' && cell.glyph <= '~' {
			glyph = byte(cell.glyph)
		}
		state.buffer[state.buffer_len] = glyph
		state.buffer_len += 1
		state.cursor_x += 1
	}
	return true
}

@(private)
ansi_flush :: proc(data: rawptr) -> bool {
	state := (^Ansi_Backend)(data)
	if state == nil {
		return false
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 4) {
		return false
	}
	ansi_append(state, "\x1b[0m")
	state.style, state.style_known = {}, true
	return ansi_drain(state)
}
