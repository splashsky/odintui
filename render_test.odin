package odintui

import "base:runtime"
import "core:testing"

@(private)
Call :: struct {
	x, y, count: int,
}

@(private)
Mock_Backend :: struct {
	calls: [64]Call,
	count, flushes: int,
	fail_draw_at: int,
	fail_flush: bool,
	screen: [8][8]Cell,
}

@(private)
mock_draw :: proc(data: rawptr, x, y: int, cells: []Cell) -> bool {
	mock := (^Mock_Backend)(data)
	mock.calls[mock.count] = {x, y, len(cells)}
	mock.count += 1
	for cell, i in cells {
		mock.screen[y][x+i] = cell
	}
	return mock.fail_draw_at != mock.count
}

@(private)
mock_flush :: proc(data: rawptr) -> bool {
	mock := (^Mock_Backend)(data)
	mock.flushes += 1
	return !mock.fail_flush
}

@(private)
mock_backend :: proc(mock: ^Mock_Backend) -> Backend {
	return {mock, mock_draw, mock_flush}
}

@(test)
test_render_diffs_and_invalidation :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 2 && mock.flushes == 1)
	testing.expect(t, mock.calls[0] == Call{0, 0, 5})
	testing.expect(t, mock.calls[1] == Call{0, 1, 5})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 2 && mock.flushes == 1)

	set_cell(&grid, 0, 0, {'a', {}})
	set_cell(&grid, 1, 0, {'b', {}})
	set_cell(&grid, 3, 0, {'c', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 4 && mock.flushes == 2)
	testing.expect(t, mock.calls[2] == Call{0, 0, 2})
	testing.expect(t, mock.calls[3] == Call{3, 0, 1})
	set_cell(&grid, 1, 0, {'!', {}})
	set_cell(&grid, 1, 0, {'b', {}})
	testing.expect(t, render(&grid, Backend{}))
	testing.expect(t, mock.count == 4 && mock.flushes == 2)

	set_cell(&grid, 1, 0, {'b', Style{bg = rgb(4, 5, 6), attributes = {.Italic}}})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 5 && mock.calls[4] == Call{1, 0, 1})
	invalidate(&grid)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 7 && mock.flushes == 4)
	testing.expect(t, grid_resize(&grid, 3, 1) == .None)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 8 && mock.calls[7] == Call{0, 0, 3})
}

@(test)
test_render_commits_multiple_later_rows :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))

	set_cell(&grid, 1, 2, {'a', {}})
	set_cell(&grid, 1, 3, {'b', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[4] == Call{1, 2, 1})
	testing.expect(t, mock.calls[5] == Call{1, 3, 1})

	set_cell(&grid, 1, 3, BLANK_CELL)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 7 && mock.calls[6] == Call{1, 3, 1})
	testing.expect(t, mock.screen[3][1] == BLANK_CELL)

	set_cell(&grid, 1, 2, BLANK_CELL)
	set_cell(&grid, 1, 3, {'c', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[7] == Call{1, 2, 1})
	testing.expect(t, mock.calls[8] == Call{1, 3, 1})
	testing.expect(t, mock.screen[2][1] == BLANK_CELL)
	testing.expect(t, mock.screen[3][1].glyph == 'c')
}

@(test)
test_render_retry_after_partial_draw_and_changes :: proc(t: ^testing.T) {
	grid, err := grid_init(3, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))
	set_cell(&grid, 0, 0, {'a', {}})
	set_cell(&grid, 1, 1, {'b', {}})
	mock.fail_draw_at = mock.count + 2
	testing.expect(t, !render(&grid, backend))
	testing.expect(t, mock.flushes == 1)
	// The first failed attempt wrote 'a', so reverting it must still be sent.
	set_cell(&grid, 0, 0, BLANK_CELL)
	mock.fail_draw_at = 0
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[4] == Call{0, 0, 3})
	testing.expect(t, mock.calls[5] == Call{0, 1, 3})
	testing.expect(t, mock.screen[0][0] == BLANK_CELL)
	testing.expect(t, mock.screen[1][1].glyph == 'b')
	testing.expect(t, mock.flushes == 2)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 6 && mock.flushes == 2)
}

@(test)
test_render_retry_after_missing_callback :: proc(t: ^testing.T) {
	grid, err := grid_init(3, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))

	set_cell(&grid, 1, 1, {'x', {}})
	testing.expect(t, !render(&grid, Backend{user_data = &mock, flush = mock_flush}))
	testing.expect(t, mock.count == 2 && mock.flushes == 1)
	set_cell(&grid, 1, 1, BLANK_CELL)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 4 && mock.flushes == 2)
	testing.expect(t, mock.calls[2] == Call{0, 0, 3})
	testing.expect(t, mock.calls[3] == Call{0, 1, 3})

	set_cell(&grid, 1, 0, {'y', {}})
	testing.expect(t, !render(&grid, Backend{user_data = &mock, draw_run = mock_draw}))
	testing.expect(t, mock.count == 4 && mock.flushes == 2)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 6 && mock.flushes == 3)
	testing.expect(t, mock.calls[4] == Call{0, 0, 3})
	testing.expect(t, mock.calls[5] == Call{0, 1, 3})
	testing.expect(t, mock.screen[0][1].glyph == 'y')
}

@(test)
test_render_retry_after_flush_failure :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	mock.fail_flush = true
	testing.expect(t, !render(&grid, backend))
	testing.expect(t, mock.count == 1 && mock.flushes == 1)
	set_cell(&grid, 0, 0, {'x', {}})
	mock.fail_flush = false
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.count == 2 && mock.flushes == 2)
	testing.expect(t, mock.calls[1] == Call{0, 0, 2})
	testing.expect(t, mock.screen[0][0].glyph == 'x')
	testing.expect(t, render(&grid, Backend{}))
	set_cell(&grid, 1, 0, {'y', {}})
	testing.expect(t, !render(&grid, Backend{}))
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.screen[0][1].glyph == 'y')
	set_cell(&grid, 0, 0, {'z', {}})
	mock.fail_flush = true
	testing.expect(t, !render(&grid, backend))
	set_cell(&grid, 0, 0, {'x', {}})
	mock.fail_flush = false
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[mock.count-1] == Call{0, 0, 2})
	testing.expect(t, mock.screen[0][0].glyph == 'x')
}

@(test)
test_render_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(3, 2, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, state.remaining == 0)
	testing.expect(t, render(&grid, backend))
	draw_text(&grid, 0, 1, "abc")
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.screen[1][2].glyph == 'c')
}

@(test)
test_render_styled_spaces :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))

	black := Cell{glyph = ' ', style = {fg = rgb(0, 0, 0)}}
	testing.expect(t, black != BLANK_CELL)
	set_cell(&grid, 1, 0, black)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[1] == Call{1, 0, 1})
	testing.expect(t, mock.screen[0][1] == black)

	black.style.attributes = {.Bold}
	set_cell(&grid, 1, 0, black)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[2] == Call{1, 0, 1})
	testing.expect(t, mock.screen[0][1] == black)

	set_cell(&grid, 1, 0, BLANK_CELL)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[3] == Call{1, 0, 1})
	testing.expect(t, mock.screen[0][1] == BLANK_CELL)
}

@(test)
test_failed_resize_preserves_pending_diff :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(2, 1, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	mock: Mock_Backend
	backend := mock_backend(&mock)
	testing.expect(t, render(&grid, backend))
	set_cell(&grid, 1, 0, {'x', {}})
	testing.expect(t, grid_resize(&grid, 3, 1) == .Allocation_Failed)
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 2, 1})
	testing.expect(t, render(&grid, backend))
	testing.expect(t, mock.calls[1] == Call{1, 0, 1})
	testing.expect(t, mock.screen[0][1].glyph == 'x')
}
