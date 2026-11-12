package odintui

import "core:testing"

@(test)
wide_test_width_policy :: proc(t: ^testing.T) {
	for r in "●○◐▸◆▣⇄█▀▄" { testing.expect(t, rune_width(r) == 1) }
	testing.expect(t, rune_width('界') == 2 && rune_width('🙂') == 2)
	// Regional indicators have Emoji_Presentation despite East_Asian_Width=N.
	testing.expect(t, rune_width('🇦') == 2)
	testing.expect(t, rune_width('\u0301') == 0 && rune_width('\u200d') == 0)
	testing.expect(t, rune_width('\ufe0f') == 0 && rune_width('a') == 1)
	testing.expect(t, text_width("A界🙂e\u0301") == 6)
}

@(test)
wide_test_clips_overwrite_and_resize :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{fg = rgb(1, 2, 3)}
	draw_text(&grid, 1, 0, "界A", style)
	box_test_cell(t, &grid, 1, 0, {'界', style})
	box_test_cell(t, &grid, 2, 0, {CONTINUATION, style})
	box_test_cell(t, &grid, 3, 0, {'A', style})
	_ = push_clip(&grid, {2, 0, 3, 1})
	set_cell(&grid, 2, 0, {'x', style})
	box_test_cell(t, &grid, 1, 0, {' ', style}) // partner cleared beyond clip
	box_test_cell(t, &grid, 2, 0, {'x', style})
	draw_text(&grid, 1, 0, "界界界", style)
	box_test_cell(t, &grid, 2, 0, {' ', style})
	box_test_cell(t, &grid, 3, 0, {'界', style})
	box_test_cell(t, &grid, 4, 0, {CONTINUATION, style})
	pop_clip(&grid)
	set_cell(&grid, 4, 1, {'界', style})
	testing.expect(t, grid_resize(&grid, 5, 2) == .None)
	box_test_cell(t, &grid, 4, 1, {' ', style})
	box_test_cell(t, &grid, 3, 0, {'界', style})
	box_test_cell(t, &grid, 4, 0, {CONTINUATION, style})
}

@(test)
wide_test_wrap_truncate_and_ellipsis :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	lines, widest := measure_text("a界b", 2, .Char)
	testing.expect(t, lines == 3 && widest == 2)
	_ = draw_paragraph(&grid, {0, 0, 2, 3}, "a界b", {}, {wrap = .Char})
	text_expect_row(t, &grid, 0, "a ")
	text_expect_row(t, &grid, 1, "界")
	text_expect_row(t, &grid, 2, "b ")
	lines, widest = measure_text("界🙂", 1, .Char)
	testing.expect(t, lines == 2 && widest == 1)
	_ = draw_paragraph(&grid, {3, 0, 1, 2}, "界🙂", {}, {wrap = .Char})
	box_test_cell(t, &grid, 3, 0, BLANK_CELL)
	box_test_cell(t, &grid, 3, 1, BLANK_CELL)
	_ = draw_paragraph(&grid, {4, 0, 3, 1}, "a界b", {}, {ellipsis = true})
	box_test_cell(t, &grid, 4, 0, {'a', {}})
	box_test_cell(t, &grid, 5, 0, {' ', {}})
	box_test_cell(t, &grid, 6, 0, {'…', {}})
	_ = draw_paragraph(&grid, {0, 3, 8, 1}, "x\u0301\u200d\ufe0f界")
	box_test_cell(t, &grid, 1, 3, {'界', {}})
	box_test_cell(t, &grid, 2, 3, {CONTINUATION, {}})
}

@(test)
wide_test_ansi_diffs_and_cursor :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer: ansi_Test_Writer
	ansi := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&ansi)
	draw_text(&grid, 0, 0, "界x")
	testing.expect(t, render(&grid, backend))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m界x \x1b[0m")
	writer.len = 0
	set_cell(&grid, 0, 0, {'語', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m語\x1b[0m")
	writer.len = 0
	set_cell(&grid, 1, 0, {'z', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m z\x1b[0m")
}

@(test)
wide_test_field_cursor_and_mask :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	buffer: [32]byte
	field := text_field_init(buffer[:], "A界B")
	text_field_home(&field)
	text_field_right(&field)
	x, _, visible := draw_text_field(&grid, {0, 0, 5, 1}, &field, {focused = true})
	testing.expect(t, visible && x == 1)
	box_test_cell(t, &grid, 1, 0, {'界', {attributes = {.Reverse}}})
	box_test_cell(t, &grid, 2, 0, {CONTINUATION, {attributes = {.Reverse}}})
	text_field_end(&field)
	x, _, visible = draw_text_field(&grid, {0, 1, 3, 1}, &field, {focused = true, mask = '界'})
	testing.expect(t, visible && x == 2 && field.scroll == 2)
	box_test_cell(t, &grid, 0, 1, {'界', {}})
	box_test_cell(t, &grid, 1, 1, {CONTINUATION, {}})
	box_test_cell(t, &grid, 2, 1, {' ', {attributes = {.Reverse}}})
}

@(test)
wide_test_random_grid_invariants :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	seed: u32 = 0x13459
	glyphs := [5]rune{'A', '界', '🙂', ' ', '◐'}
	for iteration in 0..<1200 {
		seed = seed*1664525 + 1013904223
		x := int(seed % 10)-1
		y := int((seed >> 8) % 3)
		glyph := glyphs[int((seed >> 16) % u32(len(glyphs)))]
		_ = push_clip(&grid, {int((seed >> 5) % 5), 0, int((seed >> 12) % 5), 3})
		if iteration % 3 == 0 {
			fill(&grid, x, y, int((seed >> 20) % 5)+1, 1, {glyph, {}})
		} else {
			set_cell(&grid, x, y, {glyph, {}})
		}
		pop_clip(&grid)
		if iteration % 100 == 0 {
			_ = grid_resize(&grid, 7, 3)
			_ = grid_resize(&grid, 8, 3)
		}
		for row in 0..<grid.height {
			for column in 0..<grid.width {
				cell, _ := get_cell(&grid, column, row)
				if cell.glyph == CONTINUATION {
					testing.expect(t, column > 0)
					if column > 0 {
						lead, _ := get_cell(&grid, column-1, row)
						testing.expect(t, rune_width(lead.glyph) == 2 && lead.style == cell.style)
					}
				} else if rune_width(cell.glyph) == 2 {
					testing.expect(t, column+1 < grid.width)
					if column+1 < grid.width {
						tail, _ := get_cell(&grid, column+1, row)
						testing.expect(t, tail.glyph == CONTINUATION && tail.style == cell.style)
					}
				}
			}
		}
	}
}
