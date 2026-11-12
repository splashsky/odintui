package odintui

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
		{"\x1b[57352;2u", {key = .Up, modifiers = {.Shift}}},
		{"\x1b[57375u", {key = .F12}},
		{"\x1b[99999999999999999999999999999~", {key = .Unknown}},
		{"\x1b[65;17u", {key = .Unknown}},
		{"\x1b[55296u", {key = .Unknown}},
		{"\x1b[1114112u", {key = .Unknown}},
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
