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
