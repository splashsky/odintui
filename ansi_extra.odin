package odintui

import "core:unicode"
import "core:unicode/utf8"

// Strings in OSC sequences are decoded and stripped of controls and invalid
// UTF-8. Never pass an unsanitized application string to ansi_append.
@(private)
ansi_sanitized :: proc(state: ^Ansi_Backend, text: string) -> bool {
	for i := 0; i < len(text); {
		r, n := utf8.decode_rune_in_string(text[i:])
		i += n
		if (r == utf8.RUNE_ERROR && n == 1) || unicode.is_control(r) { continue }
		if !ansi_reserve(state, 4) { return false }
		encoded, size := utf8.encode_rune(r)
		state.buffer_len += copy(state.buffer[state.buffer_len:], encoded[:size])
	}
	return true
}

// Ansi_Cursor_Shape selects DECSCUSR's default, blinking/steady block,
// underline or bar. Its zero value restores the terminal default.
Ansi_Cursor_Shape :: enum {
	Default,
	Blinking_Block,
	Steady_Block,
	Blinking_Underline,
	Steady_Underline,
	Blinking_Bar,
	Steady_Bar,
}

// ansi_set_cursor_shape writes DECSCUSR immediately, between frames.
ansi_set_cursor_shape :: proc(state: ^Ansi_Backend, shape: Ansi_Cursor_Shape) -> bool {
	if state == nil || int(shape) < 0 || int(shape) > 6 { return false }
	ansi_prepare(state)
	if !ansi_reserve(state, 32) { return false }
	ansi_append(state, "\x1b[")
	ansi_number(state, u64(shape))
	ansi_append(state, " q")
	return ansi_drain(state)
}

// ansi_set_title writes OSC 2 immediately, stripping C0, DEL, C1 and invalid
// UTF-8. The caller owns text; no copy is retained.
ansi_set_title :: proc(state: ^Ansi_Backend, title: string) -> bool {
	if state == nil { return false }
	ansi_prepare(state)
	if !ansi_reserve(state, 16) { return false }
	ansi_append(state, "\x1b]2;")
	if !ansi_sanitized(state, title) || !ansi_reserve(state, 2) { return false }
	ansi_append(state, "\x1b\\")
	return ansi_drain(state)
}

// ANSI_CLIPBOARD_MAX is the maximum raw OSC 52 payload, before base64.
ANSI_CLIPBOARD_MAX :: 100 * 1024

// ansi_set_clipboard writes an OSC 52 clipboard selection immediately. Data is
// base64-encoded, including arbitrary binary bytes; oversized data is rejected
// without writing anything. This only requests a write: terminal policy may
// disable clipboard access. Call between frames.
ansi_set_clipboard :: proc(state: ^Ansi_Backend, data: []byte) -> bool {
	if state == nil || len(data) > ANSI_CLIPBOARD_MAX { return false }
	ansi_prepare(state)
	if !ansi_reserve(state, 16) { return false }
	ansi_append(state, "\x1b]52;c;")
	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i := 0; i < len(data); i += 3 {
		if !ansi_reserve(state, 4) { return false }
		n := min(3, len(data)-i)
		bits := u32(data[i]) << 16
		if n > 1 { bits |= u32(data[i+1]) << 8 }
		if n > 2 { bits |= u32(data[i+2]) }
		state.buffer[state.buffer_len] = alphabet[int((bits >> 18) & 63)]
		state.buffer[state.buffer_len+1] = alphabet[int((bits >> 12) & 63)]
		state.buffer[state.buffer_len+2] = '='
		state.buffer[state.buffer_len+3] = '='
		if n > 1 { state.buffer[state.buffer_len+2] = alphabet[int((bits >> 6) & 63)] }
		if n > 2 { state.buffer[state.buffer_len+3] = alphabet[int(bits & 63)] }
		state.buffer_len += 4
	}
	if !ansi_reserve(state, 2) { return false }
	ansi_append(state, "\x1b\\")
	return ansi_drain(state)
}
