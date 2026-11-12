package odintui

import "base:runtime"
import "core:testing"

@(private)
table_test_row :: proc(t: ^testing.T, grid: ^Grid, y: int, expected: string) {
	x := 0
	for glyph in expected {
		cell, ok := get_cell(grid, x, y)
		testing.expect(t, ok && cell.glyph == glyph)
		x += 1
	}
}

@(private)
table_test_cell :: proc(t: ^testing.T, grid: ^Grid, x, y: int, expected: Cell) {
	cell, ok := get_cell(grid, x, y)
	testing.expect(t, ok && cell == expected)
}

@(test)
table_test_default_render_and_styles :: proc(t: ^testing.T) {
	grid, err := grid_init(11, 7)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 11, 7, {'.', {}})
	columns := []Table_Column{{title = "Name"}, {title = "Qty", align = .End}}
	rows := [][]string{{"A", "12", "ignored"}, {"B"}}
	base := Style{fg = rgb(1, 2, 3), attributes = {.Italic}}
	border := Style{fg = rgb(4, 5, 6)}
	state := List_State{selected = 1}
	body := draw_table(&grid, grid_bounds(&grid), columns, rows, &state, {
		style = base, border_style = border,
	})
	testing.expect(t, body == Rect{1, 3, 9, 3})
	table_test_row(t, &grid, 0, "┌────┬────┐")
	table_test_row(t, &grid, 1, "│Name│ Qty│")
	table_test_row(t, &grid, 2, "├────┼────┤")
	table_test_row(t, &grid, 3, "│A   │  12│")
	table_test_row(t, &grid, 4, "│B   │    │")
	table_test_row(t, &grid, 5, "│    │    │")
	table_test_row(t, &grid, 6, "└────┴────┘")
	header := base
	header.attributes += {.Bold}
	selected := base
	selected.attributes += {.Reverse}
	table_test_cell(t, &grid, 1, 1, {'N', header})
	table_test_cell(t, &grid, 8, 1, {'t', header})
	table_test_cell(t, &grid, 1, 3, {'A', base})
	table_test_cell(t, &grid, 1, 4, {'B', selected})
	table_test_cell(t, &grid, 4, 4, {' ', selected})
	table_test_cell(t, &grid, 7, 4, {' ', selected})
	table_test_cell(t, &grid, 5, 4, {'│', border})
	table_test_cell(t, &grid, 5, 2, {'┼', border})
}

@(test)
table_test_row_lines_scrolling_and_hit_testing :: proc(t: ^testing.T) {
	grid, err := grid_init(12, 7)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	columns := []Table_Column{{}, {}}
	rows := [][]string{{"0", "a"}, {"1", "b"}, {"2", "c"}, {"3", "d"}, {"4", "e"}, {"5", "f"}}
	state := List_State{selected = 4, offset = 0}
	options := Table_Options{border = BORDER_DOUBLE, no_header = true, row_lines = true, padding = 1}
	row, ok := table_row_at(grid_bounds(&grid), columns, len(rows), &state, 2, 1, options)
	testing.expect(t, ok && row == 2 && state.offset == 0)
	body := draw_table(&grid, grid_bounds(&grid), columns, rows, &state, options)
	testing.expect(t, body == Rect{1, 1, 10, 5} && state.offset == 2 && state.selected == 4)
	table_test_row(t, &grid, 0, "╔═════╦════╗")
	table_test_row(t, &grid, 1, "║ 2   ║ c  ║")
	table_test_row(t, &grid, 2, "╠═════╬════╣")
	table_test_row(t, &grid, 3, "║ 3   ║ d  ║")
	table_test_row(t, &grid, 4, "╠═════╬════╣")
	table_test_row(t, &grid, 5, "║ 4   ║ e  ║")
	table_test_row(t, &grid, 6, "╚═════╩════╝")
	table_test_cell(t, &grid, 1, 5, {' ', {attributes = {.Reverse}}})
	for y in 1..<6 {
		row, ok = table_row_at(grid_bounds(&grid), columns, len(rows), &state, 2, y, options)
		if y%2 == 0 {
			testing.expect(t, !ok)
		} else {
			testing.expect(t, ok && row == 2+y/2)
		}
	}
	_, ok = table_row_at(grid_bounds(&grid), columns, len(rows), &state, 0, 1, options)
	testing.expect(t, !ok)
	state = {selected = 50, offset = -5}
	draw_table(&grid, grid_bounds(&grid), columns, rows[:2], &state, options)
	testing.expect(t, state.selected == 1 && state.offset == 0)
	table_test_row(t, &grid, 2, "╠═════╬════╣")
	table_test_row(t, &grid, 4, "║     ║    ║")
	_, ok = table_row_at(grid_bounds(&grid), columns, 2, &state, 2, 5, options)
	testing.expect(t, !ok)
	draw_table(&grid, grid_bounds(&grid), columns, rows[:0], &state, options)
	testing.expect(t, state == List_State{})
}

@(test)
table_test_borderless_constraints_padding_and_clip :: proc(t: ^testing.T) {
	grid, err := grid_init(15, 5)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 15, 5, {'.', {}})
	columns := []Table_Column{
		{title = "first", width = layout_fixed(3)},
		{title = "second", width = layout_percent(25), align = .End},
		{title = "third", width = layout_fill(1, 0, 2)},
	}
	rows := [][]string{{"a", "long", "hidden"}, {"z", "b"}}
	options := Table_Options{borderless = true, no_column_lines = true, padding = 1}
	testing.expect(t, push_clip(&grid, {3, 1, 7, 3}))
	body := draw_table(&grid, {1, 1, 13, 4}, columns, rows, nil, options)
	pop_clip(&grid)
	testing.expect(t, body == Rect{1, 3, 13, 2})
	table_test_row(t, &grid, 1, "...  …    .....")
	table_test_row(t, &grid, 2, "...───────.....")
	table_test_row(t, &grid, 3, "...  …    .....")
	table_test_row(t, &grid, 4, "...............")
	row, ok := table_row_at({1, 1, 13, 4}, columns, 2, nil, 1, 4, options)
	testing.expect(t, ok && row == 1)
}

@(test)
table_test_scrollbars_and_custom_styles :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 7)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	columns := []Table_Column{{title = "head"}}
	rows := [][]string{{"0"}, {"1"}, {"2"}, {"3"}, {"4"}, {"5"}}
	state := List_State{selected = 5}
	header := Style{fg = rgb(4, 5, 6)}
	selected := Style{bg = rgb(7, 8, 9)}
	track := Style{fg = rgb(10, 11, 12)}
	options := Table_Options{
		header_style = header, selected_style = selected, scrollbar = true,
		scrollbar_options = {track = '.', thumb = '#', track_style = track, thumb_style = track},
	}
	draw_table(&grid, grid_bounds(&grid), columns, rows, &state, options)
	testing.expect(t, state.offset == 3)
	table_test_cell(t, &grid, 1, 1, {'h', header})
	table_test_cell(t, &grid, 1, 5, {'5', selected})
	table_test_cell(t, &grid, 7, 3, {'.', track})
	table_test_cell(t, &grid, 7, 4, {'.', track})
	table_test_cell(t, &grid, 7, 5, {'#', track})
	table_test_cell(t, &grid, 7, 6, {'┘', {}})
	options.borderless = true
	options.no_header = true
	draw_table(&grid, {0, 0, 5, 3}, columns, rows, &state, options)
	table_test_cell(t, &grid, 4, 2, {'#', track})
}

@(test)
table_test_column_limit_and_narrow_bounds :: proc(t: ^testing.T) {
	grid, err := grid_init(35, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	columns: [MAX_TABLE_COLUMNS+1]Table_Column
	values: [MAX_TABLE_COLUMNS+1]string
	for i in 0..<len(columns) {
		columns[i] = {width = layout_fixed(1)}
		values[i] = "x"
	}
	values[MAX_TABLE_COLUMNS] = "z"
	rows := [][]string{values[:]}
	draw_table(&grid, {0, 0, 35, 1}, columns[:], rows, nil, {
		borderless = true, no_header = true, no_column_lines = true,
	})
	table_test_cell(t, &grid, 31, 0, {'x', {}})
	table_test_cell(t, &grid, 32, 0, BLANK_CELL)
	_, ok := table_row_at({0, 0, 35, 1}, columns[:], 1, nil, 32, 0, {
		borderless = true, no_header = true, no_column_lines = true,
	})
	testing.expect(t, ok)
	draw_table(&grid, {0, 1, 1, 1}, columns[:], rows)
	table_test_cell(t, &grid, 0, 1, {'┘', {}})
	draw_table(&grid, {0, 2, 3, 2}, columns[:], rows)
	table_test_cell(t, &grid, 0, 2, {'┌', {}})
	table_test_cell(t, &grid, 2, 3, {'┘', {}})
	draw_table(&grid, {min(int), min(int), max(int), max(int)}, columns[:], rows)
	draw_table(&grid, {max(int), max(int), max(int), max(int)}, columns[:], rows)
	draw_table(&grid, {0, 0, -1, 2}, columns[:], rows, nil, {scrollbar = true})
}

@(test)
table_test_drawing_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(8, 5, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	columns := []Table_Column{{title = "head"}, {title = "end"}}
	rows := [][]string{{"abc", "def"}, {"ghi"}, {"jkl", "mno"}}
	selection := List_State{selected = 2}
	options := Table_Options{scrollbar = true, row_lines = true}
	body := draw_table(&grid, grid_bounds(&grid), columns, rows, &selection, options)
	row, ok := table_row_at(grid_bounds(&grid), columns, len(rows), &selection, 1, 3, options)
	testing.expect(t, body == Rect{1, 3, 6, 1} && ok && row == 2)
	table_test_cell(t, &grid, 1, 3, {'j', {attributes = {.Reverse}}})
	testing.expect(t, state.remaining == 0)
}
