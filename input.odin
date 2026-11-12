package odintui

// Key identifies a decoded terminal key.
Key :: enum {
	Rune,
	Enter,
	Tab,
	Backspace,
	Escape,
	Up,
	Down,
	Left,
	Right,
	Home,
	End,
	Page_Up,
	Page_Down,
	Insert,
	Delete,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	Unknown,
}

// Modifier identifies a keyboard or mouse modifier.
Modifier :: enum {
	Shift,
	Alt,
	Ctrl,
	Super,
}

// Modifiers is a set of active keyboard or mouse modifiers.
Modifiers :: bit_set[Modifier; u8]

// Key_Event contains a key and, for Rune, its decoded Unicode scalar.
Key_Event :: struct {
	key:       Key,
	rune:      rune,
	modifiers: Modifiers,
}

// Input_Event is a decoded terminal input event.
Input_Event :: union {
	Key_Event,
}

// Input_Parser retains streaming state; its zero value is ready to use.
Input_Parser :: struct {}

// input_parse decodes one event without allocation. Retain all unconsumed
// bytes and append new input before retrying when consumed is zero. Set final
// after an escape timeout or at EOF to resolve incomplete input; nonempty
// input then always makes progress. Empty input always consumes zero bytes.
input_parse :: proc(parser: ^Input_Parser, data: []byte, final := false) -> (Input_Event, int) {
	_ = parser
	if len(data) == 0 {
		return nil, 0
	}
	if data[0] == 0x1b {
		if len(data) == 1 {
			if !final {
				return nil, 0
			}
			return Key_Event{key = .Escape}, 1
		}
		event, consumed := input_key(data[1:], final)
		if consumed == 0 {
			return nil, 0
		}
		event.modifiers += {.Alt}
		return event, consumed+1
	}
	event, consumed := input_key(data, final)
	if consumed == 0 {
		return nil, 0
	}
	return event, consumed
}

@(private)
input_key :: proc(data: []byte, final: bool) -> (Key_Event, int) {
	b := data[0]
	switch b {
	case 0:
		return {.Rune, ' ', {.Ctrl}}, 1
	case 8, 0x7f:
		return {key = .Backspace}, 1
	case 9:
		return {key = .Tab}, 1
	case 10, 13:
		return {key = .Enter}, 1
	case 0x1b:
		return {key = .Escape}, 1
	case 1..<27:
		return {.Rune, rune('a') + rune(b) - 1, {.Ctrl}}, 1
	case 28..<32:
		return {.Rune, rune('\\') + rune(b) - 28, {.Ctrl}}, 1
	}
	if b < 0x80 {
		return {.Rune, rune(b), {}}, 1
	}

	size := 0
	value: rune
	switch {
	case b >= 0xc2 && b <= 0xdf:
		size, value = 2, rune(b & 0x1f)
	case b >= 0xe0 && b <= 0xef:
		size, value = 3, rune(b & 0x0f)
	case b >= 0xf0 && b <= 0xf4:
		size, value = 4, rune(b & 0x07)
	case:
		return {.Rune, '\uFFFD', {}}, 1
	}
	for i in 1..<min(size, len(data)) {
		c := data[i]
		if c < 0x80 || c > 0xbf ||
		   (i == 1 && ((b == 0xe0 && c < 0xa0) || (b == 0xed && c >= 0xa0) ||
		               (b == 0xf0 && c < 0x90) || (b == 0xf4 && c >= 0x90))) {
			return {.Rune, '\uFFFD', {}}, 1
		}
		value = (value << 6) | rune(c & 0x3f)
	}
	if len(data) < size {
		if !final {
			return {}, 0
		}
		return {.Rune, '\uFFFD', {}}, 1
	}
	return {.Rune, value, {}}, size
}
