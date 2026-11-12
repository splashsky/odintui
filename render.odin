package odintui

// draw_run writes a contiguous horizontal run; cells are borrowed for the call.
// flush commits the writes. Both callbacks return false on failure and must
// tolerate retries. They must not mutate the grid or retain the cells slice.
// A backend must sanitize control/invalid runes and map glyphs to single cells.
Backend :: struct {
	user_data: rawptr,
	draw_run:  proc(user_data: rawptr, x, y: int, cells: []Cell) -> bool,
	flush:     proc(user_data: rawptr) -> bool,
}

// invalidate forces the next render to redraw the entire nonempty grid.
invalidate :: proc(grid: ^Grid) {
	grid.presented_valid = false
	for &row in grid.dirty {
		row = {0, grid.width}
	}
	grid.dirty_start, grid.dirty_end = 0, len(grid.dirty)
}

// render sends changed runs and commits them only after a successful flush.
// After failure it redraws everything, even if the grid changes before retry.
// A failed backend may have applied partial writes; retries must resynchronize.
// An unchanged or empty grid does not call the backend. Call invalidate when
// switching backends or when the backend's contents have been lost.
// The grid and backend require exclusive access during render and callbacks.
render :: proc(grid: ^Grid, backend: Backend) -> bool {
	if grid.dirty_start == grid.dirty_end {
		return true
	}

	changed := false
	for row, i in grid.dirty[grid.dirty_start:grid.dirty_end] {
		y := grid.dirty_start + i
		x := row.start
		for x < row.end {
			index := y*grid.width + x
			if grid.presented_valid && grid.cells[index] == grid.presented[index] {
				x += 1
				continue
			}
			start := x
			for x < row.end {
				index = y*grid.width + x
				if grid.presented_valid && grid.cells[index] == grid.presented[index] {
					break
				}
				x += 1
			}
			changed = true
			if backend.draw_run == nil || backend.flush == nil {
				invalidate(grid)
				return false
			}
			offset := y * grid.width
			if !backend.draw_run(backend.user_data, start, y, grid.cells[offset+start:offset+x]) {
				invalidate(grid)
				return false
			}
		}
	}
	if changed && !backend.flush(backend.user_data) {
		invalidate(grid)
		return false
	}
	for &row, i in grid.dirty[grid.dirty_start:grid.dirty_end] {
		y := grid.dirty_start + i
		if row.start != row.end {
			offset := y * grid.width
			copy(grid.presented[offset+row.start:offset+row.end],
			     grid.cells[offset+row.start:offset+row.end])
			row = {}
		}
	}
	grid.dirty_start, grid.dirty_end = 0, 0
	grid.presented_valid = true
	return true
}
