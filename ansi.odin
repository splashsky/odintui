package odintui

import "core:io"
import "core:unicode"
import "core:unicode/utf8"

// Ansi_Color_Mode selects RGB, xterm 256-color, or basic 16-color output.
Ansi_Color_Mode :: enum {
	Truecolor,
	Color_256,
	Color_16,
}

// Ansi_Terminal_Mode selects optional terminal modes controlled by the host.
Ansi_Terminal_Mode :: enum {
	Alt_Screen,
	Hide_Cursor,
	Mouse,
	Bracketed_Paste,
	Focus,
	Kitty_Keyboard,
}

// Ansi_Terminal_Modes is a set of terminal modes.
Ansi_Terminal_Modes :: bit_set[Ansi_Terminal_Mode; u8]

// Ansi_Backend batches output to writer; flush resets SGR and writes the buffer.
// Do not copy it or modify its internal state while in use. The writer must
// outlive the backend, and calls require exclusive access to both.
// A zero replacement or an unsafe replacement uses '?'. Ambiguous-width
// characters are treated as narrow, as in unicode.normalized_east_asian_width.
// Cursor and SGR are cached only between runs of the same frame. Short writes
// fail; a retry cancels any interrupted escape before resynchronizing.
Ansi_Backend :: struct {
	writer:       io.Writer,
	color_mode:   Ansi_Color_Mode,
	replacement:  rune,
	buffer:       [4096]byte,
	buffer_len:   int,
	cursor_x:     int,
	cursor_y:     int,
	cursor_known: bool,
	style:        Style,
	style_known:  bool,
	style_mode:   Ansi_Color_Mode,
	cancel:       bool,
}

// ansi_backend returns callbacks borrowing state; state must outlive the Backend.
ansi_backend :: proc(state: ^Ansi_Backend) -> Backend {
	return {state, ansi_draw_run, ansi_flush}
}

// ansi_enter writes the selected mode sequences immediately, between renders.
// Mouse enables SGR coordinates and button/drag tracking; kitty enables its
// basic keyboard mode.
// Kitty pushes a mode, so a failed enter may require host-managed recovery.
// Invalidate the grid after switching screens. The host owns terminal setup.
ansi_enter :: proc(state: ^Ansi_Backend, modes: Ansi_Terminal_Modes) -> bool {
	if state == nil {
		return false
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 128) {
		return false
	}
	if .Alt_Screen in modes {
		ansi_append(state, "\x1b[?1049h")
		state.cursor_known, state.style_known = false, false
	}
	if .Hide_Cursor in modes {
		ansi_append(state, "\x1b[?25l")
	}
	if .Mouse in modes {
		ansi_append(state, "\x1b[?1002h\x1b[?1006h")
	}
	if .Bracketed_Paste in modes {
		ansi_append(state, "\x1b[?2004h")
	}
	if .Focus in modes {
		ansi_append(state, "\x1b[?1004h")
	}
	if .Kitty_Keyboard in modes {
		ansi_append(state, "\x1b[>1u")
	}
	ok := ansi_drain(state)
	state.cursor_known, state.style_known = false, false
	return ok
}

// ansi_leave reverses selected modes, then resets style and shows the cursor.
// A failure can leave modes partially changed; the host must handle cleanup.
ansi_leave :: proc(state: ^Ansi_Backend, modes: Ansi_Terminal_Modes) -> bool {
	if state == nil {
		return false
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 128) {
		return false
	}
	if .Kitty_Keyboard in modes {
		ansi_append(state, "\x1b[<u")
	}
	if .Focus in modes {
		ansi_append(state, "\x1b[?1004l")
	}
	if .Bracketed_Paste in modes {
		ansi_append(state, "\x1b[?2004l")
	}
	if .Mouse in modes {
		ansi_append(state, "\x1b[?1006l\x1b[?1002l")
	}
	if .Hide_Cursor in modes {
		ansi_append(state, "\x1b[?25h")
	}
	if .Alt_Screen in modes {
		ansi_append(state, "\x1b[?1049l")
		state.cursor_known = false
	}
	ansi_append(state, "\x1b[0m\x1b[?25h")
	ok := ansi_drain(state)
	state.cursor_known, state.style_known = false, false
	return ok
}

// ansi_clear resets style, clears the screen, and moves home immediately.
// Call invalidate on the grid after clearing or resizing the terminal.
ansi_clear :: proc(state: ^Ansi_Backend) -> bool {
	if state == nil {
		return false
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 16) {
		return false
	}
	ansi_append(state, "\x1b[0m\x1b[2J\x1b[H")
	ok := ansi_drain(state)
	state.cursor_known, state.style_known = false, false
	return ok
}

// ansi_set_cursor positions the real cursor at zero-based x,y and shows or
// hides it immediately. Negative and unrepresentable coordinates fail.
ansi_set_cursor :: proc(state: ^Ansi_Backend, x, y: int, visible: bool) -> bool {
	if state == nil {
		return false
	}
	if x < 0 || y < 0 || x == max(int) || y == max(int) {
		ansi_fail(state)
		return false
	}
	ansi_prepare(state)
	if !ansi_reserve(state, 64) {
		return false
	}
	ansi_move(state, x, y)
	if visible {
		ansi_append(state, "\x1b[?25h")
	} else {
		ansi_append(state, "\x1b[?25l")
	}
	ok := ansi_drain(state)
	state.cursor_known, state.style_known = false, false
	return ok
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
	state.style, state.style_known, state.style_mode = style, true, state.color_mode
}

@(private)
ansi_color :: proc(state: ^Ansi_Backend, color: Color, foreground: bool) {
	if state.color_mode == .Color_16 {
		index := ansi_color_16(color)
		code := 30 + index
		if index >= 8 {
			code = 90 + index-8
		}
		if !foreground {
			code += 10
		}
		ansi_append(state, ";")
		ansi_number(state, u64(code))
		return
	}
	if foreground {
		ansi_append(state, ";38;")
	} else {
		ansi_append(state, ";48;")
	}
	if state.color_mode == .Color_256 {
		ansi_append(state, "5;")
		ansi_number(state, u64(ansi_color_256(color)))
		return
	}
	ansi_append(state, "2;")
	ansi_number(state, u64(color.r))
	ansi_append(state, ";")
	ansi_number(state, u64(color.g))
	ansi_append(state, ";")
	ansi_number(state, u64(color.b))
}

@(private)
ansi_distance :: proc(color: Color, r, g, b: int) -> int {
	dr, dg, db := int(color.r)-r, int(color.g)-g, int(color.b)-b
	return dr*dr + dg*dg + db*db
}

@(private)
ansi_color_256 :: proc(color: Color) -> int {
	levels := [6]int{0, 95, 135, 175, 215, 255}
	channels := [3]int{int(color.r), int(color.g), int(color.b)}
	index: [3]int
	for channel, i in channels {
		for j in 1..<len(levels) {
			if abs(channel-levels[j]) < abs(channel-levels[index[i]]) {
				index[i] = j
			}
		}
	}
	cube := 16+36*index[0]+6*index[1]+index[2]
	cube_distance := ansi_distance(color, levels[index[0]], levels[index[1]], levels[index[2]])
	gray := clamp((channels[0]+channels[1]+channels[2]-24+15)/30, 0, 23)
	value := 8+10*gray
	if ansi_distance(color, value, value, value) < cube_distance {
		return 232+gray
	}
	return cube
}

@(private)
ansi_color_16 :: proc(color: Color) -> int {
	palette := [16][3]int{
		{0, 0, 0}, {128, 0, 0}, {0, 128, 0}, {128, 128, 0},
		{0, 0, 128}, {128, 0, 128}, {0, 128, 128}, {192, 192, 192},
		{128, 128, 128}, {255, 0, 0}, {0, 255, 0}, {255, 255, 0},
		{0, 0, 255}, {255, 0, 255}, {0, 255, 255}, {255, 255, 255},
	}
	best, distance := 0, max(int)
	for rgb, i in palette {
		d := ansi_distance(color, rgb[0], rgb[1], rgb[2])
		if d < distance {
			best, distance = i, d
		}
	}
	return best
}

@(private)
ansi_single_column :: proc(glyph: rune) -> bool {
	if glyph >= ' ' && glyph <= '~' {
		return true
	}
	if glyph < 0 || glyph > 0x10ffff || (glyph >= 0xd800 && glyph <= 0xdfff) ||
	   (glyph >= 0x1160 && glyph <= 0x11ff) || (glyph >= 0xd7b0 && glyph <= 0xd7ff) {
		return false
	}
	return unicode.is_printable(glyph) &&
	       !unicode.is_combining(glyph) &&
	       !unicode.is_nonspacing_mark(glyph) &&
	       !unicode.is_spacing_mark(glyph) &&
	       !unicode.is_enclosing_mark(glyph) &&
	       !unicode.is_gcb_extend_class(glyph) &&
	       unicode.normalized_east_asian_width(glyph) == 1
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
		if !state.style_known || state.style != cell.style || state.style_mode != state.color_mode {
			ansi_style(state, cell.style)
		}
		glyph := cell.glyph
		if !ansi_single_column(glyph) {
			glyph = state.replacement
			if !ansi_single_column(glyph) {
				glyph = '?'
			}
		}
		encoded, n := utf8.encode_rune(glyph)
		state.buffer_len += copy(state.buffer[state.buffer_len:], encoded[:n])
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
	ok := ansi_drain(state)
	state.cursor_known, state.style_known = false, false
	return ok
}
