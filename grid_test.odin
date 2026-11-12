package odintui

import "base:runtime"
import "core:mem"
import "core:testing"

@(test)
test_grid_drawing_and_clipping :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)

	cell, ok := get_cell(&grid, 0, 0)
	testing.expect(t, ok && cell == BLANK_CELL)
	_, ok = get_cell(&grid, -1, 0)
	testing.expect(t, !ok)
	testing.expect(t, !set_cell(&grid, 4, 0, {'x', {}}))
	testing.expect(t, !set_cell(&grid, 0, 3, {'x', {}}))

	style := Style{fg = rgb(1, 2, 3), attributes = {.Bold, .Underline}}
	draw_text(&grid, -1, 0, "aé界🙂z", style)
	cell, ok = get_cell(&grid, 0, 0)
	testing.expect(t, ok && cell == Cell{'é', style})
	cell, _ = get_cell(&grid, 1, 0)
	testing.expect(t, cell == Cell{'界', style})
	cell, _ = get_cell(&grid, 2, 0)
	testing.expect(t, cell == Cell{'🙂', style})
	cell, _ = get_cell(&grid, 3, 0)
	testing.expect(t, cell == Cell{'z', style})
	draw_text(&grid, min(int), 0, "hello", style)
	draw_text(&grid, 0, -1, "hello", style)

	fill(&grid, -2, 1, max(int), max(int), {'#', style})
	for y in 1..<3 {
		for x in 0..<4 {
			cell, _ = get_cell(&grid, x, y)
			testing.expect(t, cell == Cell{'#', style})
		}
	}
	fill(&grid, min(int), 0, max(int), 1, {'!', {}})
	fill(&grid, 0, min(int), 1, max(int), {'!', {}})
	fill(&grid, 0, 0, -1, 1, {'!', {}})
	cell, _ = get_cell(&grid, 0, 0)
	testing.expect(t, cell == Cell{'é', style})
}

@(test)
test_resize_and_empty_grids :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 2, 2})
	set_cell(&grid, 1, 1, {'X', {}})
	testing.expect(t, grid_resize(&grid, 3, 3) == .None)
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 3, 3})
	cell, _ := get_cell(&grid, 1, 1)
	testing.expect(t, cell.glyph == 'X')
	cell, _ = get_cell(&grid, 2, 2)
	testing.expect(t, cell == BLANK_CELL)
	testing.expect(t, grid_resize(&grid, 1, 2) == .None)
	_, ok := get_cell(&grid, 1, 1)
	testing.expect(t, !ok)
	cell, _ = get_cell(&grid, 0, 0)
	testing.expect(t, cell == BLANK_CELL)
	testing.expect(t, grid_resize(&grid, 0, max(int)) == .None)
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 0, max(int)})
	draw_text(&grid, 0, max(int)-1, "x")
	fill(&grid, 0, 0, max(int), max(int), {'x', {}})
	fill(&grid, -1, 0, 2, max(int), {'x', {}})
	testing.expect(t, render(&grid, {}) && len(grid.cells) == 0)
	testing.expect(t, grid_resize(&grid, max(int), 0) == .None)
	testing.expect(t, grid_resize(&grid, -1, 1) == .Invalid_Dimensions)
	testing.expect(t, grid_resize(&grid, max(int), 2) == .Invalid_Dimensions)
	testing.expect(t, grid_resize(&grid, max(int), 1) == .Invalid_Dimensions)
	testing.expect(t, grid.width == max(int) && grid.height == 0)
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, max(int), 0})
	testing.expect(t, grid_resize(&grid, 2, 1) == .None)
	cell, _ = get_cell(&grid, 1, 0)
	testing.expect(t, cell == BLANK_CELL)
	grid_destroy(&grid)
	grid_destroy(&grid)
}

@(private)
Failing_Allocator :: struct {
	backing: runtime.Allocator,
	remaining: int,
}

@(private)
failing_allocator_proc :: proc(
	data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int,
	old_memory: rawptr, old_size: int, location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	state := (^Failing_Allocator)(data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		if state.remaining == 0 {
			return nil, .Out_Of_Memory
		}
		state.remaining -= 1
	}
	return state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, location)
}

@(test)
test_allocation_failure_preserves_grid :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	state := Failing_Allocator{backing = mem.tracking_allocator(&tracker)}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	invalid, invalid_err := grid_init(-1, 2, allocator)
	testing.expect(t, invalid_err == .Invalid_Dimensions)
	grid_destroy(&invalid)
	for stage in 0..<3 {
		state.remaining = stage
		failed, err := grid_init(2, 2, allocator)
		testing.expect(t, err == .Allocation_Failed)
		grid_destroy(&failed)
		testing.expect(t, len(tracker.allocation_map) == 0)
	}
	state.remaining = 3
	grid, err := grid_init(2, 2, allocator)
	testing.expect(t, err == .None)
	set_cell(&grid, 1, 1, {'X', {}})
	for stage in 0..<3 {
		state.remaining = stage
		testing.expect(t, grid_resize(&grid, 3, 3) == .Allocation_Failed)
		cell, ok := get_cell(&grid, 1, 1)
		testing.expect(t, ok && cell.glyph == 'X')
		testing.expect(t, grid.width == 2 && grid.height == 2)
		testing.expect(t, len(tracker.allocation_map) == 3)
	}
	grid_destroy(&grid)
	testing.expect(t, len(tracker.allocation_map) == 0)
}

@(test)
test_text_invalid_utf8 :: proc(t: ^testing.T) {
	grid, err := grid_init(3, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	invalid := [3]byte{'a', 0xff, 'b'}
	draw_text(&grid, 0, 0, string(invalid[:]))
	cell, _ := get_cell(&grid, 0, 0)
	testing.expect(t, cell.glyph == 'a')
	cell, _ = get_cell(&grid, 1, 0)
	testing.expect(t, cell.glyph == '\uFFFD')
	cell, _ = get_cell(&grid, 2, 0)
	testing.expect(t, cell.glyph == 'b')
}

@(test)
test_grid_nested_clips_and_resize :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	pop_clip(&grid)
	testing.expect(t, current_clip(&grid) == grid_bounds(&grid))
	testing.expect(t, push_clip(&grid, Rect{1, 0, 6, 3}))
	testing.expect(t, current_clip(&grid) == Rect{1, 0, 4, 3})
	testing.expect(t, push_clip(&grid, Rect{2, 1, 2, 2}))
	testing.expect(t, current_clip(&grid) == Rect{2, 1, 2, 2})
	testing.expect(t, !set_cell(&grid, 1, 1, {'!', {}}))
	testing.expect(t, set_cell(&grid, 2, 1, {'x', {}}))
	cell, ok := get_cell(&grid, 1, 1)
	testing.expect(t, ok && cell == BLANK_CELL)
	draw_text(&grid, 0, 1, "abcde")
	fill(&grid, -1, 2, max(int), 1, {'f', {}})
	draw_border(&grid, Rect{0, 0, 5, 3})
	cell, _ = get_cell(&grid, 2, 1)
	testing.expect(t, cell.glyph == 'c')
	cell, _ = get_cell(&grid, 3, 1)
	testing.expect(t, cell.glyph == 'd')
	cell, _ = get_cell(&grid, 2, 2)
	testing.expect(t, cell.glyph == '-')
	cell, _ = get_cell(&grid, 4, 2)
	testing.expect(t, cell == BLANK_CELL)
	pop_clip(&grid)

	testing.expect(t, grid_resize(&grid, 3, 3) == .None)
	testing.expect(t, current_clip(&grid) == Rect{1, 0, 2, 3})
	testing.expect(t, grid_resize(&grid, 8, 3) == .None)
	testing.expect(t, current_clip(&grid) == Rect{1, 0, 6, 3})
	pop_clip(&grid)
	testing.expect(t, current_clip(&grid) == grid_bounds(&grid))
	testing.expect(t, push_clip(&grid, Rect{min(int), 0, max(int), 1}))
	testing.expect(t, rect_is_empty(current_clip(&grid)))
	testing.expect(t, !set_cell(&grid, 0, 0, {'!', {}}))
	grid_destroy(&grid)
	testing.expect(t, grid.clip_depth == 0)
}

@(test)
test_grid_clip_scope :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	{
		if clip_scope(&grid, Rect{1, 1, 2, 2}) {
			testing.expect(t, current_clip(&grid) == Rect{1, 1, 2, 2})
			if clip_scope(&grid, Rect{2, 0, 2, 4}) {
				testing.expect(t, current_clip(&grid) == Rect{2, 1, 1, 2})
			}
			testing.expect(t, current_clip(&grid) == Rect{1, 1, 2, 2})
		}
		testing.expect(t, current_clip(&grid) == grid_bounds(&grid))
	}
	for _ in 0..<MAX_CLIP_DEPTH {
		testing.expect(t, push_clip(&grid, Rect{1, 1, 2, 2}))
	}
	{
		if clip_scope(&grid, Rect{0, 0, 1, 1}) {
			testing.expect(t, false)
		}
	}
	testing.expect(t, grid.clip_depth == MAX_CLIP_DEPTH)
	for _ in 0..<MAX_CLIP_DEPTH {
		pop_clip(&grid)
	}
	testing.expect(t, current_clip(&grid) == grid_bounds(&grid))
}

@(test)
test_grid_clipped_drawing_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(4, 3, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	testing.expect(t, state.remaining == 0)
	{
		if clip_scope(&grid, Rect{1, 1, 2, 1}) {
			fill(&grid, 0, 0, 4, 3, {'x', {}})
			draw_text(&grid, 0, 1, "abcd")
			draw_label(&grid, Rect{0, 1, 4, 1}, "1234")
			set_cell(&grid, 2, 1, {'z', {}})
		}
	}
	cell, _ := get_cell(&grid, 1, 1)
	testing.expect(t, cell.glyph == '2')
	cell, _ = get_cell(&grid, 2, 1)
	testing.expect(t, cell.glyph == 'z')
	cell, _ = get_cell(&grid, 0, 1)
	testing.expect(t, cell == BLANK_CELL)
}

@(test)
test_grid_fill_dirty_ranges_and_render :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))
	set_cell(&grid, 2, 1, {'x', {}})
	set_cell(&grid, 4, 1, {'x', {}})
	testing.expect(t, render(&grid, backend))
	count := mock.count

	testing.expect(t, push_clip(&grid, Rect{1, 1, 4, 2}))
	fill(&grid, -1, 0, max(int), 3, {'x', {}})
	testing.expect(t, grid.dirty_start == 1 && grid.dirty_end == 3)
	testing.expect(t, grid.dirty[0] == Dirty_Row{})
	testing.expect(t, grid.dirty[1] == Dirty_Row{1, 4})
	testing.expect(t, grid.dirty[2] == Dirty_Row{1, 5})
	testing.expect(t, grid.dirty[3] == Dirty_Row{})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == count+3)
	testing.expect(t, mock.calls[count] == Call{1, 1, 1})
	testing.expect(t, mock.calls[count+1] == Call{3, 1, 1})
	testing.expect(t, mock.calls[count+2] == Call{1, 2, 4})
	fill(&grid, 0, 0, 6, 4, {'x', {}})
	testing.expect(t, grid.dirty_start == grid.dirty_end)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == count+3)

	set_cell(&grid, 1, 1, {'!', {}})
	fill(&grid, 2, 1, 1, 1, {'y', {}})
	testing.expect(t, grid.dirty[1] == Dirty_Row{1, 3})
	fill(&grid, 1, 1, 1, 1, {'x', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[count+3] == Call{2, 1, 1})
	pop_clip(&grid)
}

@(test)
test_grid_extended_attributes_render :: proc(t: ^testing.T) {
	grid, err := grid_init(1, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))
	style := Style{attributes = {.Bold, .Italic, .Underline, .Reverse,
	                            .Dim, .Blink, .Hidden, .Strikethrough}}
	set_cell(&grid, 0, 0, {'x', style})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.screen[0][0] == Cell{'x', style})
	set_cell(&grid, 0, 0, {'x', style})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 2)
	style.attributes -= {.Strikethrough, .Hidden}
	set_cell(&grid, 0, 0, {'x', style})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 3 && mock.screen[0][0] == Cell{'x', style})
}

@(test)
test_grid_hex_colors :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator}
	context.allocator = {procedure = failing_allocator_proc, data = &state}
	valid := [5]struct{input: string, expected: Color} {
		{"#Ab3", rgb(170, 187, 51)},
		{"f09", rgb(255, 0, 153)},
		{"#123aBc", rgb(18, 58, 188)},
		{"Ff00Aa", rgb(255, 0, 170)},
		{"000", rgb(0, 0, 0)},
	}
	for item in valid {
		color, ok := hex(item.input)
		testing.expect(t, ok && color == item.expected)
	}
	invalid := [12]string{
		"", "#", "ab", "#abcd", "abcdef0", "##123", "#12g",
		"12345g", " 123", "123\n", "ééé", "\x00123",
	}
	for input in invalid {
		color, ok := hex(input)
		testing.expect(t, !ok && color == Color{})
	}
}
