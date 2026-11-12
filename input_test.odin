package odintui

import "base:runtime"
import "core:testing"

@(test)
input_test_text_and_controls :: proc(t: ^testing.T) {
	cases := []struct {
		text:     string,
		expected: Key_Event,
		consumed: int,
	}{
		{"x", {.Rune, 'x', {}}, 1},
		{"é", {.Rune, 'é', {}}, 2},
		{"界", {.Rune, '界', {}}, 3},
		{"🙂", {.Rune, '🙂', {}}, 4},
		{"\x00", {.Rune, ' ', {.Ctrl}}, 1},
		{"\x01", {.Rune, 'a', {.Ctrl}}, 1},
		{"\x1a", {.Rune, 'z', {.Ctrl}}, 1},
		{"\x1c", {.Rune, '\\', {.Ctrl}}, 1},
		{"\x08", {key = .Backspace}, 1},
		{"\x7f", {key = .Backspace}, 1},
		{"\t", {key = .Tab}, 1},
		{"\r", {key = .Enter}, 1},
		{"\n", {key = .Enter}, 1},
		{"\x1bx", {.Rune, 'x', {.Alt}}, 2},
		{"\x1bPnext", {.Rune, 'P', {.Alt}}, 2},
		{"\x1b]next", {.Rune, ']', {.Alt}}, 2},
		{"\x1b next", {.Rune, ' ', {.Alt}}, 2},
		{"\x1b!next", {.Rune, '!', {.Alt}}, 2},
		{"\x1b\x01", {.Rune, 'a', {.Alt, .Ctrl}}, 2},
		{"\x1bé", {.Rune, 'é', {.Alt}}, 3},
		{"\xff", {.Rune, '\uFFFD', {}}, 1},
		{"\xe0\x80", {.Rune, '\uFFFD', {}}, 1},
		{"\xed\xa0\x80", {.Rune, '\uFFFD', {}}, 1},
		{"\xf4\x90\x80\x80", {.Rune, '\uFFFD', {}}, 1},
	}
	parser: Input_Parser
	for c in cases {
		event, consumed := input_parse(&parser, transmute([]byte)c.text)
		key, ok := event.(Key_Event)
		testing.expect(t, ok && key == c.expected && consumed == c.consumed)
	}
}

@(test)
input_test_incomplete_text :: proc(t: ^testing.T) {
	parser: Input_Parser
	cases := []string{"\x1b", "\xc3", "\xf0\x9f", "\x1b\xc3"}
	for text in cases {
		data := transmute([]byte)text
		_, consumed := input_parse(&parser, data)
		testing.expect(t, consumed == 0)
		event, n := input_parse(&parser, data, true)
		key, ok := event.(Key_Event)
		testing.expect(t, ok && n > 0 && n <= len(data))
		if text == "\x1b" {
			testing.expect(t, key.key == .Escape)
		} else {
			testing.expect(t, key.rune == '\uFFFD')
		}
	}
	_, consumed := input_parse(&parser, nil, true)
	testing.expect(t, consumed == 0)
}

@(test)
input_test_escape_keys :: proc(t: ^testing.T) {
	cases := []struct {
		text:     string,
		expected: Key_Event,
	}{
		{"\x1b[A", {key = .Up}},
		{"\x1b[B", {key = .Down}},
		{"\x1b[C", {key = .Right}},
		{"\x1b[D", {key = .Left}},
		{"\x1b[H", {key = .Home}},
		{"\x1b[F", {key = .End}},
		{"\x1b[1;5A", {key = .Up, modifiers = {.Ctrl}}},
		{"\x1b[1;16D", {key = .Left, modifiers = {.Shift, .Alt, .Ctrl, .Super}}},
		{"\x1b[Z", {key = .Tab, modifiers = {.Shift}}},
		{"\x1bOP", {key = .F1}},
		{"\x1bOQ", {key = .F2}},
		{"\x1bOR", {key = .F3}},
		{"\x1bOS", {key = .F4}},
		{"\x1bO1;3P", {key = .F1, modifiers = {.Alt}}},
		{"\x1b[[A", {key = .F1}},
		{"\x1b[[E", {key = .F5}},
		{"\x1b[1~", {key = .Home}},
		{"\x1b[4~", {key = .End}},
		{"\x1b[2~", {key = .Insert}},
		{"\x1b[3;2~", {key = .Delete, modifiers = {.Shift}}},
		{"\x1b[5~", {key = .Page_Up}},
		{"\x1b[6~", {key = .Page_Down}},
		{"\x1b[15~", {key = .F5}},
		{"\x1b[17~", {key = .F6}},
		{"\x1b[18~", {key = .F7}},
		{"\x1b[19~", {key = .F8}},
		{"\x1b[20~", {key = .F9}},
		{"\x1b[21~", {key = .F10}},
		{"\x1b[23~", {key = .F11}},
		{"\x1b[24~", {key = .F12}},
		{"\x1b[97;5u", {.Rune, 'a', {.Ctrl}}},
		{"\x1b[128578;3u", {.Rune, '🙂', {.Alt}}},
		{"\x1b[27u", {key = .Escape}},
		{"\x1b[0u", {.Rune, ' ', {.Ctrl}}},
		{"\x1b[3;3u", {.Rune, 'c', {.Alt, .Ctrl}}},
		{"\x1b[8;5u", {key = .Backspace, modifiers = {.Ctrl}}},
		{"\x1b[10u", {key = .Enter}},
		{"\x1b[57352;2u", {key = .Up, modifiers = {.Shift}}},
		{"\x1b[57375u", {key = .F12}},
		{"\x1b[99999999999999999999999999999~", {key = .Unknown}},
		{"\x1b[65;17u", {key = .Unknown}},
		{"\x1b[55296u", {key = .Unknown}},
		{"\x1b[1114112u", {key = .Unknown}},
		{"\x1b[;5u", {key = .Unknown}},
		{"\x1bO97;5u", {key = .Unknown}},
		{"\x1bO2~", {key = .Unknown}},
		{"\x1b[?25h", {key = .Unknown}},
		{"\x1b[1;2:3A", {key = .Unknown}},
	}
	parser: Input_Parser
	for c in cases {
		data := transmute([]byte)c.text
		for i in 1..<len(data) {
			_, consumed := input_parse(&parser, data[:i])
			testing.expect(t, consumed == 0)
		}
		event, consumed := input_parse(&parser, data)
		key, ok := event.(Key_Event)
		testing.expect(t, ok && key == c.expected && consumed == len(data))
	}
}

@(test)
input_test_unknown_escape_progress :: proc(t: ^testing.T) {
	parser: Input_Parser
	data := transmute([]byte)string("\x1b[\x1bx")
	event, consumed := input_parse(&parser, data)
	key, ok := event.(Key_Event)
	testing.expect(t, ok && key.key == .Unknown && consumed == 2)
	event, consumed = input_parse(&parser, data[consumed:])
	key, ok = event.(Key_Event)
	testing.expect(t, ok && key == Key_Event{.Rune, 'x', {.Alt}} && consumed == 2)
}

@(test)
input_test_incomplete_escape :: proc(t: ^testing.T) {
	parser: Input_Parser
	cases := []string{"\x1b[", "\x1b[1;", "\x1bO"}
	for text in cases {
		data := transmute([]byte)text
		_, consumed := input_parse(&parser, data)
		testing.expect(t, consumed == 0)
		event, n := input_parse(&parser, data, true)
		key, ok := event.(Key_Event)
		testing.expect(t, ok && key.key == .Rune && key.modifiers == {.Alt})
		testing.expect(t, n == 2 && key.rune == rune(data[1]))
	}
}

@(test)
input_test_mouse :: proc(t: ^testing.T) {
	cases := []struct {
		text:     string,
		expected: Mouse_Event,
	}{
		{"\x1b[<0;1;1M", {0, 0, .Left, .Press, {}}},
		{"\x1b[<1;80;25M", {79, 24, .Middle, .Press, {}}},
		{"\x1b[<2;5;3m", {4, 2, .Right, .Release, {}}},
		{"\x1b[<3;1;1M", {0, 0, .None, .Release, {}}},
		{"\x1b[<35;12;13M", {11, 12, .None, .Move, {}}},
		{"\x1b[<60;12;13M", {11, 12, .Left, .Drag, {.Shift, .Alt, .Ctrl}}},
		{"\x1b[<64;1;1M", {0, 0, .Wheel_Up, .Press, {}}},
		{"\x1b[<65;1;1M", {0, 0, .Wheel_Down, .Press, {}}},
		{"\x1b[<66;1;1M", {0, 0, .Wheel_Left, .Press, {}}},
		{"\x1b[<67;1;1M", {0, 0, .Wheel_Right, .Press, {}}},
	}
	parser: Input_Parser
	for c in cases {
		data := transmute([]byte)c.text
		for i in 1..<len(data) {
			_, consumed := input_parse(&parser, data[:i])
			testing.expect(t, consumed == 0)
		}
		event, consumed := input_parse(&parser, data)
		mouse, ok := event.(Mouse_Event)
		testing.expect(t, ok && mouse == c.expected && consumed == len(data))
	}
	invalid := []string{
		"\x1b[<;1;1M",
		"\x1b[<0;0;1M",
		"\x1b[<0;1;0M",
		"\x1b[<0;99999999999999999999999999;1M",
		"\x1b[<128;1;1M",
		"\x1b[<64;1;1m",
		"\x1b[<0;1;1;2M",
	}
	for text in invalid {
		event, consumed := input_parse(&parser, transmute([]byte)text)
		key, ok := event.(Key_Event)
		testing.expect(t, ok && key.key == .Unknown && consumed == len(text))
	}
}

@(test)
input_test_focus_and_paste :: proc(t: ^testing.T) {
	parser: Input_Parser
	cases := []string{"\x1b[I", "\x1b[O"}
	for text in cases {
		event, consumed := input_parse(&parser, transmute([]byte)text)
		focus, ok := event.(Focus_Event)
		testing.expect(t, ok && focus.focused == (text == "\x1b[I") && consumed == len(text))
	}
	data := transmute([]byte)string("\x1b[200~ab\x1b[A\x00\x1b[201~z")
	event, consumed := input_parse(&parser, data)
	start, ok := event.(Paste_Event)
	testing.expect(t, ok && start.kind == .Start && consumed == 6)
	data = data[consumed:]
	event, consumed = input_parse(&parser, data)
	chunk, chunk_ok := event.(Paste_Event)
	testing.expect(t, chunk_ok && chunk.kind == .Chunk && string(chunk.text) == "ab\x1b[A\x00")
	testing.expect(t, &chunk.text[0] == &data[0] && consumed == len(chunk.text))
	data = data[consumed:]
	event, consumed = input_parse(&parser, data)
	end, end_ok := event.(Paste_Event)
	testing.expect(t, end_ok && end.kind == .End && consumed == 6)
	data = data[consumed:]
	event, consumed = input_parse(&parser, data)
	key, key_ok := event.(Key_Event)
	testing.expect(t, key_ok && key.rune == 'z' && consumed == 1)
}

@(test)
input_test_paste_split_marker :: proc(t: ^testing.T) {
	parser: Input_Parser
	_, _ = input_parse(&parser, transmute([]byte)string("\x1b[200~"))
	marker := transmute([]byte)string("\x1b[201~")
	for i in 1..<len(marker) {
		_, consumed := input_parse(&parser, marker[:i])
		testing.expect(t, consumed == 0)
	}
	data := transmute([]byte)string("abc\x1b[20")
	event, consumed := input_parse(&parser, data)
	chunk, ok := event.(Paste_Event)
	testing.expect(t, ok && chunk.kind == .Chunk && string(chunk.text) == "abc" && consumed == 3)
	_, consumed = input_parse(&parser, data[3:])
	testing.expect(t, consumed == 0)
	event, consumed = input_parse(&parser, data[3:], true)
	chunk, ok = event.(Paste_Event)
	testing.expect(t, ok && chunk.kind == .Chunk && string(chunk.text) == "\x1b[20" && consumed == 4)
	event, consumed = input_parse(&parser, marker)
	end, end_ok := event.(Paste_Event)
	testing.expect(t, end_ok && end.kind == .End && consumed == len(marker))

	// A mismatched partial marker is paste text, not an escape sequence.
	_, _ = input_parse(&parser, transmute([]byte)string("\x1b[200~"))
	event, consumed = input_parse(&parser, transmute([]byte)string("\x1b[20X"))
	chunk, ok = event.(Paste_Event)
	testing.expect(t, ok && chunk.kind == .Chunk && string(chunk.text) == "\x1b[20X" && consumed == 5)
}

@(test)
input_test_bytewise_stream_and_iterator :: proc(t: ^testing.T) {
	source := "é\x1b[1;5A\x1b[200~A\x1b[A🙂\x1b[201~\x1b[Iz"
	buffer: [128]byte
	size := 0
	parser: Input_Parser
	paste_text: [128]byte
	paste_size, starts, ends, keys, focuses := 0, 0, 0, 0, 0
	for b in transmute([]byte)source {
		buffer[size] = b
		size += 1
		pending := buffer[:size]
		for event in input_next(&parser, &pending) {
			switch e in event {
			case Key_Event:
				switch keys {
				case 0: testing.expect(t, e.key == .Rune && e.rune == 'é')
				case 1: testing.expect(t, e.key == .Up && e.modifiers == {.Ctrl})
				case 2: testing.expect(t, e.key == .Rune && e.rune == 'z')
				case: testing.expect(t, false)
				}
				keys += 1
			case Paste_Event:
				switch e.kind {
				case .Start: starts += 1
				case .End: ends += 1
				case .Chunk:
					copy(paste_text[paste_size:], e.text)
					paste_size += len(e.text)
				}
			case Focus_Event:
				testing.expect(t, e.focused)
				focuses += 1
			case Mouse_Event:
				testing.expect(t, false)
			case:
				testing.expect(t, false)
			}
		}
		copy(buffer[:], pending)
		size = len(pending)
	}
	testing.expect(t, size == 0 && starts == 1 && ends == 1 && keys == 3 && focuses == 1)
	testing.expect(t, string(paste_text[:paste_size]) == "A\x1b[A🙂")

	pending := transmute([]byte)string("\x1b")
	for _ in input_next(&parser, &pending) {
		testing.expect(t, false)
	}
	testing.expect(t, len(pending) == 1)
	for event in input_next(&parser, &pending, true) {
		key, ok := event.(Key_Event)
		testing.expect(t, ok && key.key == .Escape)
	}
	testing.expect(t, len(pending) == 0)
}

@(test)
input_test_no_allocations :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	valid := true
	count := 0
	{
		previous := context.allocator
		context.allocator = allocator
		defer context.allocator = previous
		parser: Input_Parser
		pending := transmute([]byte)string("é\x1b[1;5A\x1b[<0;4;2M\x1b[I\x1b[200~\x1b[A\x1b[201~x")
		for event in input_next(&parser, &pending) {
			valid = valid && event != nil
			count += 1
		}
		valid = valid && len(pending) == 0
	}
	testing.expect(t, valid && count == 8 && state.remaining == 0)
}

@(test)
input_test_random_progress :: proc(t: ^testing.T) {
	state: u64 = 0x1234_5678_9abc_def0
	buffer: [64]byte
	for iteration in 0..<12000 {
		for &b in buffer {
			state = state ~ (state << 13)
			state = state ~ (state >> 7)
			state = state ~ (state << 17)
			b = byte(state & 0xff)
		}
		parser: Input_Parser
		if iteration % 3 == 0 {
			_, _ = input_parse(&parser, transmute([]byte)string("\x1b[200~"))
		} else if iteration % 3 == 1 {
			buffer[0], buffer[1] = 0x1b, '['
		}
		pending := buffer[:int(state%u64(len(buffer)))+1]
		for len(pending) > 0 {
			_, consumed := input_parse(&parser, pending, true)
			if consumed <= 0 || consumed > len(pending) {
				testing.expect(t, false)
				break
			}
			pending = pending[consumed:]
		}
	}
}
