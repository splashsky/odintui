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
