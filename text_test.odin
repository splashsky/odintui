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
	testing.expect(t, draw_spans(&grid, grid_bounds(&grid), spans, {wrap = .Word}) == 3)
	testing.expect(t, draw_paragraph(&grid, grid_bounds(&grid), "abc def", {}, {wrap = .Char}) == 1)
	lines, widest := measure_spans(spans, 8, .Word)
	testing.expect(t, lines == 3 && widest == 5)
	lines, widest = measure_text("abcd", 2, .Char)
	testing.expect(t, lines == 2 && widest == 2)
	testing.expect(t, state.remaining == 0)
}
