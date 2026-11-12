package odintui

import "base:runtime"
import "core:testing"

@(private)
text_expect_row :: proc(t: ^testing.T, grid: ^Grid, y: int, expected: string) {
	x := 0
	for glyph in expected {
		cell, ok := get_cell(grid, x, y)
		testing.expect(t, ok && cell.glyph == glyph)
		x += 1
	}
}

@(test)
text_test_spans_alignment_and_clipping :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 8, 4, {'.', {}})
	red := Style{fg = rgb(255, 0, 0)}
	bold := Style{attributes = {.Bold}}
	spans := []Span{
		{"A", red},
		{"界\r", bold},
		{"\nB", red},
	}
	testing.expect(t, push_clip(&grid, Rect{2, 0, 4, 4}))
	lines := draw_spans(&grid, Rect{0, 0, 7, 4}, spans, {align = .Center})
	pop_clip(&grid)
	testing.expect(t, lines == 2)
	text_expect_row(t, &grid, 0, "..A界....")
	text_expect_row(t, &grid, 1, "...B....")
	cell, _ := get_cell(&grid, 2, 0)
	testing.expect(t, cell.style == red)
	cell, _ = get_cell(&grid, 3, 0)
	testing.expect(t, cell.style == bold)
	testing.expect(t, draw_paragraph(&grid, Rect{1, 2, 6, 1}, "xy", bold, {align = .End}) == 1)
	text_expect_row(t, &grid, 2, ".....xy.")
}

@(test)
text_test_character_wrap_and_hard_breaks :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 6)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	spans := []Span{{"ab", {}}, {"界d\r", {}}, {"\ne\n", {}}}
	lines, widest := measure_spans(spans, 2, .Char)
	testing.expect(t, lines == 4 && widest == 2)
	testing.expect(t, draw_spans(&grid, Rect{0, 0, 2, 6}, spans, {wrap = .Char}) == lines)
	text_expect_row(t, &grid, 0, "ab  ")
	text_expect_row(t, &grid, 1, "界d  ")
	text_expect_row(t, &grid, 2, "e   ")
	text_expect_row(t, &grid, 3, "    ")
	lines, widest = measure_text("ab\rX\n", 1, .None)
	testing.expect(t, lines == 2 && widest == 4)
	testing.expect(t, draw_paragraph(&grid, Rect{0, 4, 4, 1}, "a\rb") == 1)
	cell, _ := get_cell(&grid, 1, 4)
	testing.expect(t, cell.glyph == '\r')
}

@(test)
text_test_word_wrap_across_spans :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 6)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	red := Style{fg = rgb(200, 0, 0)}
	spans := []Span{{"ab  c", {}}, {"def", red}, {" gh\n", {}}}
	lines, widest := measure_spans(spans, 4, .Word)
	testing.expect(t, lines == 4 && widest == 4)
	testing.expect(t, draw_spans(&grid, Rect{0, 0, 4, 6}, spans, {wrap = .Word}) == lines)
	text_expect_row(t, &grid, 0, "ab   ")
	text_expect_row(t, &grid, 1, "cdef ")
	text_expect_row(t, &grid, 2, "gh   ")
	text_expect_row(t, &grid, 3, "     ")
	cell, _ := get_cell(&grid, 1, 1)
	testing.expect(t, cell.style == red)
	lines, widest = measure_text("word    \nnext", 4, .Word)
	testing.expect(t, lines == 2 && widest == 4)
	testing.expect(t, draw_paragraph(&grid, Rect{0, 4, 4, 2}, "word    \nnext", {}, {wrap = .Word}) == 2)
	text_expect_row(t, &grid, 4, "word ")
	text_expect_row(t, &grid, 5, "next ")
}

@(test)
text_test_zero_sizes_and_extreme_bounds :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	lines, widest := measure_text("", 0, .None)
	testing.expect(t, lines == 1 && widest == 0)
	lines, widest = measure_text("text", 0, .Char)
	testing.expect(t, lines == 0 && widest == 0)
	testing.expect(t, draw_paragraph(&grid, Rect{0, 0, -1, 1}, "text") == 0)
	testing.expect(t, draw_paragraph(&grid, Rect{0, 0, 1, -1}, "text") == 0)
	testing.expect(t, draw_paragraph(&grid, Rect{min(int), 0, max(int), 1}, "text") == 1)
	testing.expect(t, draw_paragraph(&grid, Rect{max(int), max(int), max(int), max(int)}, "text") == 1)
	testing.expect(t, draw_paragraph(&grid, Rect{min(int), min(int), max(int), max(int)}, "a\nb") == 2)
	text_expect_row(t, &grid, 0, "    ")
	testing.expect(t, draw_paragraph(&grid, Rect{-2, 1, 4, 1}, "abcd") == 1)
	text_expect_row(t, &grid, 1, "cd  ")
}

@(test)
text_test_drawing_and_measurement_do_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(8, 4, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	spans := []Span{{"first ", {}}, {"界word\nlast", {}}}
	testing.expect(t, draw_spans(&grid, Rect{0, 0, 8, 2}, spans, {wrap = .Word, ellipsis = true}) == 2)
	testing.expect(t, draw_paragraph(&grid, grid_bounds(&grid), "abc def", {}, {wrap = .Char}) == 1)
	lines, widest := measure_spans(spans, 8, .Word)
	testing.expect(t, lines == 3 && widest == 5)
	lines, widest = measure_text("abcd", 2, .Char)
	testing.expect(t, lines == 2 && widest == 2)
	testing.expect(t, state.remaining == 0)
}

@(test)
text_test_ellipsis_and_replaced_style :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 5)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 6, 5, {'.', {}})
	red := Style{fg = rgb(255, 0, 0)}
	bold := Style{attributes = {.Bold}}
	spans := []Span{{"ab", red}, {"cdef\nx", bold}}
	lines := draw_spans(&grid, Rect{1, 0, 3, 2}, spans, {ellipsis = true})
	testing.expect(t, lines == 2)
	text_expect_row(t, &grid, 0, ".ab…..")
	text_expect_row(t, &grid, 1, ".x....")
	cell, _ := get_cell(&grid, 3, 0)
	testing.expect(t, cell.style == bold)
	testing.expect(t, draw_paragraph(&grid, Rect{1, 2, 4, 1}, "abc", red, {ellipsis = true}) == 1)
	text_expect_row(t, &grid, 2, ".abc..")
	testing.expect(t, draw_paragraph(
		&grid, Rect{1, 3, 4, 1}, "abc\nnext", red,
		{align = .End, ellipsis = true},
	) == 1)
	text_expect_row(t, &grid, 3, "..ab…")
	cell, _ = get_cell(&grid, 4, 3)
	testing.expect(t, cell.style == red)
	testing.expect(t, draw_paragraph(
		&grid, Rect{0, 4, 2, 1}, "abcd", red, {wrap = .Char, ellipsis = true},
	) == 1)
	text_expect_row(t, &grid, 4, "a…..")
}

@(test)
text_test_ellipsis_respects_clip_and_empty_lines :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 5, 2, {'.', {}})
	testing.expect(t, push_clip(&grid, Rect{0, 0, 2, 1}))
	testing.expect(t, draw_paragraph(&grid, Rect{0, 0, 4, 1}, "abcdef", {}, {ellipsis = true}) == 1)
	pop_clip(&grid)
	text_expect_row(t, &grid, 0, "ab...")
	testing.expect(t, draw_paragraph(&grid, Rect{0, 1, 4, 1}, "\nnext", {}, {ellipsis = true}) == 1)
	text_expect_row(t, &grid, 1, ".....")
}

@(test)
text_test_measurement_matches_expected_layout :: proc(t: ^testing.T) {
	cases := []struct {
		input:  string,
		width:  int,
		wrap:   Text_Wrap,
		lines:  int,
		widest: int,
		rows:   []string,
	}{
		{"", 2, .Char, 1, 0, {"........"}},
		{"\n", 2, .Char, 2, 0, {"........", "........"}},
		{"one two three", 7, .Word, 2, 7, {"one two.", "three..."}},
		{" abc  def", 4, .Word, 2, 4, {" abc....", "def....."}},
		{"abcde fgh", 3, .Word, 3, 3, {"abc.....", "de......", "fgh....."}},
		{"a    b", 2, .Word, 2, 1, {"a.......", "b......."}},
		{"      ", 2, .Word, 3, 2, {"  ......", "  ......", "  ......"}},
		{"ab\ncd\n", 2, .Char, 3, 2, {"ab......", "cd......", "........"}},
		{"ab\r\nc", 2, .Char, 2, 2, {"ab......", "c......."}},
		{"\rX", 1, .Char, 2, 1, {"\r.......", "X......."}},
		{"\xffa", 2, .Char, 1, 2, {"�a......"}},
		{"abcdef", 3, .None, 1, 6, {"abc....."}},
	}
	grid, err := grid_init(8, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	for item in cases {
		fill(&grid, 0, 0, 8, 4, {'.', {}})
		lines, widest := measure_text(item.input, item.width, item.wrap)
		testing.expect(t, lines == item.lines && widest == item.widest)
		testing.expect(t, draw_paragraph(
			&grid, Rect{0, 0, item.width, 4}, item.input, {}, {wrap = item.wrap},
		) == item.lines)
		for row in 0..<item.lines {
			text_expect_row(t, &grid, row, item.rows[row])
		}
	}
}
