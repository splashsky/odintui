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

// Mouse_Button identifies an SGR mouse button or wheel direction.
Mouse_Button :: enum {
	None,
	Left,
	Middle,
	Right,
	Wheel_Up,
	Wheel_Down,
	Wheel_Left,
	Wheel_Right,
}

// Mouse_Action distinguishes button changes and pointer motion.
Mouse_Action :: enum {
	Press,
	Release,
	Move,
	Drag,
}

// Mouse_Event contains a zero-based cell position and the mouse operation.
Mouse_Event :: struct {
	x, y:      int,
	button:    Mouse_Button,
	action:    Mouse_Action,
	modifiers: Modifiers,
}

// Paste_Kind marks the beginning, borrowed bytes, and end of a paste.
Paste_Kind :: enum {
	Start,
	Chunk,
	End,
}

// Paste_Event carries a paste boundary or a chunk borrowed from the input.
Paste_Event :: struct {
	kind: Paste_Kind,
	text: []byte,
}

// Focus_Event reports whether the terminal gained or lost focus.
Focus_Event :: struct {
	focused: bool,
}

// Input_Event is a decoded terminal input event.
Input_Event :: union {
	Key_Event,
	Mouse_Event,
	Paste_Event,
	Focus_Event,
}

// Input_Parser retains streaming state; its zero value is ready to use. Do not
// modify its fields while parsing a stream.
Input_Parser :: struct {
	in_paste: bool,
}

// input_parse decodes one event without allocation. Retain all unconsumed
// bytes and append new input before retrying when consumed is zero. Set final
// after an escape timeout or at EOF to resolve incomplete input; nonempty
// input then always makes progress. Empty input always consumes zero bytes.
// Paste chunks borrow data until the caller changes or releases that buffer.
// During a paste, use final only at EOF: a partial end marker is then text.
input_parse :: proc(parser: ^Input_Parser, data: []byte, final := false) -> (Input_Event, int) {
	if len(data) == 0 {
		return nil, 0
	}
	if parser.in_paste {
		return input_paste(parser, data, final)
	}
	if data[0] == 0x1b {
		if len(data) == 1 {
			if !final {
				return nil, 0
			}
			return Key_Event{key = .Escape}, 1
		}
		if data[1] == '[' || data[1] == 'O' {
			event, consumed := input_sequence(parser, data)
			if consumed > 0 {
				return event, consumed
			}
			if !final {
				return nil, 0
			}
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

// input_next advances pending past one decoded event. It can be used as an
// Odin for-loop iterator and stops when input_parse needs more bytes.
input_next :: proc(
	parser: ^Input_Parser,
	pending: ^[]byte,
	final := false,
) -> (event: Input_Event, ok: bool) {
	consumed: int
	event, consumed = input_parse(parser, pending^, final)
	if consumed == 0 {
		return nil, false
	}
	pending^ = pending^[consumed:]
	return event, true
}

@(private)
input_paste :: proc(parser: ^Input_Parser, data: []byte, final: bool) -> (Input_Event, int) {
	marker := "\x1b[201~"
	for i := 0; i < len(data); i += 1 {
		if data[i] != 0x1b {
			continue
		}
		matched := 0
		for matched < len(marker) && matched < len(data)-i &&
		    data[i+matched] == marker[matched] {
			matched += 1
		}
		if matched == len(marker) {
			if i > 0 {
				return Paste_Event{kind = .Chunk, text = data[:i]}, i
			}
			parser.in_paste = false
			return Paste_Event{kind = .End}, len(marker)
		}
		if matched == len(data)-i && !final {
			if i == 0 {
				return nil, 0
			}
			return Paste_Event{kind = .Chunk, text = data[:i]}, i
		}
	}
	return Paste_Event{kind = .Chunk, text = data}, len(data)
}

@(private)
input_sequence :: proc(parser: ^Input_Parser, data: []byte) -> (Input_Event, int) {
	if data[1] == '[' && len(data) > 2 && data[2] == '[' {
		if len(data) == 3 {
			return nil, 0
		}
		if data[3] >= 'A' && data[3] <= 'E' {
			return Key_Event{key = Key(int(Key.F1) + int(data[3]-'A'))}, 4
		}
		return Key_Event{key = .Unknown}, 3
	}
	for i := 2; i < len(data); i += 1 {
		b := data[i]
		if b >= 0x40 && b <= 0x7e {
			if data[1] == '[' && i == 2 && (b == 'I' || b == 'O') {
				return Focus_Event{focused = b == 'I'}, i+1
			}
			if data[1] == '[' && i == 5 && b == '~' &&
			   data[2] == '2' && data[3] == '0' && data[4] == '0' {
				parser.in_paste = true
				return Paste_Event{kind = .Start}, i+1
			}
			if data[1] == '[' && i > 2 && data[2] == '<' {
				return input_mouse(data[3:i], b), i+1
			}
			return input_sequence_key(data[2:i], b), i+1
		}
		if b < 0x20 || b > 0x3f {
			return Key_Event{key = .Unknown}, i
		}
	}
	return nil, 0
}

@(private)
input_mouse :: proc(params: []byte, final: byte) -> Input_Event {
	unknown := Key_Event{key = .Unknown}
	values, count, ok := input_params(params)
	if !ok || count != 3 || len(params) == 0 || params[0] == ';' ||
	   (final != 'M' && final != 'm') || values[0] > 127 ||
	   values[1] <= 0 || values[2] <= 0 {
		return unknown
	}
	b := values[0]
	event := Mouse_Event{x = values[1]-1, y = values[2]-1}
	if b & 4 != 0 {
		event.modifiers += {.Shift}
	}
	if b & 8 != 0 {
		event.modifiers += {.Alt}
	}
	if b & 16 != 0 {
		event.modifiers += {.Ctrl}
	}
	button := b & 3
	if b & 64 != 0 {
		if final != 'M' || b & 32 != 0 {
			return unknown
		}
		event.button = Mouse_Button(int(Mouse_Button.Wheel_Up) + button)
		event.action = .Press
		return event
	}
	switch button {
	case 0: event.button = .Left
	case 1: event.button = .Middle
	case 2: event.button = .Right
	case 3: event.button = .None
	}
	if final == 'm' || (button == 3 && b & 32 == 0) {
		event.action = .Release
	} else if b & 32 != 0 {
		if button == 3 {
			event.action = .Move
		} else {
			event.action = .Drag
		}
	} else {
		event.action = .Press
	}
	return event
}

@(private)
input_params :: proc(data: []byte) -> (values: [3]int, count: int, ok: bool) {
	if len(data) == 0 {
		return values, 0, true
	}
	count = 1
	for b in data {
		if b == ';' {
			count += 1
			if count > len(values) {
				return values, count, false
			}
		} else if b >= '0' && b <= '9' {
			digit := int(b - '0')
			if values[count-1] > (max(int)-digit)/10 {
				return values, count, false
			}
			values[count-1] = values[count-1]*10 + digit
		} else {
			return values, count, false
		}
	}
	return values, count, true
}

@(private)
input_modifiers :: proc(value: int) -> (Modifiers, bool) {
	value := value
	if value == 0 {
		value = 1
	}
	if value < 1 || value > 16 {
		return {}, false
	}
	bits := value - 1
	mods: Modifiers
	if bits & 1 != 0 {
		mods += {.Shift}
	}
	if bits & 2 != 0 {
		mods += {.Alt}
	}
	if bits & 4 != 0 {
		mods += {.Ctrl}
	}
	if bits & 8 != 0 {
		mods += {.Super}
	}
	return mods, true
}

@(private)
input_sequence_key :: proc(params: []byte, final: byte) -> Key_Event {
	unknown := Key_Event{key = .Unknown}
	values, count, ok := input_params(params)
	if !ok || count > 2 {
		return unknown
	}
	mods, valid_mods := input_modifiers(values[1])
	if !valid_mods {
		return unknown
	}
	if final == 'u' {
		if count == 0 {
			return unknown
		}
		return input_kitty_key(values[0], mods)
	}
	key := Key.Unknown
	if final == '~' && count >= 1 {
		switch values[0] {
		case 1, 7: key = .Home
		case 2:    key = .Insert
		case 3:    key = .Delete
		case 4, 8: key = .End
		case 5:    key = .Page_Up
		case 6:    key = .Page_Down
		case 11:   key = .F1
		case 12:   key = .F2
		case 13:   key = .F3
		case 14:   key = .F4
		case 15:   key = .F5
		case 17:   key = .F6
		case 18:   key = .F7
		case 19:   key = .F8
		case 20:   key = .F9
		case 21:   key = .F10
		case 23:   key = .F11
		case 24:   key = .F12
		}
	} else if values[0] == 0 || values[0] == 1 {
		switch final {
		case 'A': key = .Up
		case 'B': key = .Down
		case 'C': key = .Right
		case 'D': key = .Left
		case 'H': key = .Home
		case 'F': key = .End
		case 'P': key = .F1
		case 'Q': key = .F2
		case 'R': key = .F3
		case 'S': key = .F4
		case 'Z':
			key = .Tab
			mods += {.Shift}
		}
	}
	if key == .Unknown {
		return unknown
	}
	return {key = key, modifiers = mods}
}

@(private)
input_kitty_key :: proc(code: int, mods: Modifiers) -> Key_Event {
	event := Key_Event{key = .Rune, modifiers = mods}
	switch code {
	case 27, 57344: event.key = .Escape
	case 13, 57345: event.key = .Enter
	case 9, 57346:  event.key = .Tab
	case 127, 57347: event.key = .Backspace
	case 57348: event.key = .Insert
	case 57349: event.key = .Delete
	case 57350: event.key = .Left
	case 57351: event.key = .Right
	case 57352: event.key = .Up
	case 57353: event.key = .Down
	case 57354: event.key = .Page_Up
	case 57355: event.key = .Page_Down
	case 57356: event.key = .Home
	case 57357: event.key = .End
	case 57364..<57376:
		event.key = Key(int(Key.F1) + code - 57364)
	case:
		if code < 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) ||
		   (code >= 57358 && code <= 57454) {
			return {key = .Unknown}
		}
		event.rune = rune(code)
	}
	return event
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
