package odintui

import "base:runtime"

// A zero Color represents the backend's default color; rgb(0, 0, 0) is black.
Color :: struct {
	r, g, b: u8,
	is_rgb:  bool,
}

rgb :: proc(r, g, b: u8) -> Color {
	return {r, g, b, true}
}

// hex parses RGB hex digits in #rgb, #rrggbb, rgb, or rrggbb form.
// The letters are case-insensitive; invalid input returns a zero Color and false.
hex :: proc(s: string) -> (Color, bool) {
	digits := s
	if len(digits) > 0 && digits[0] == '#' {
		digits = digits[1:]
	}
	if len(digits) != 3 && len(digits) != 6 {
		return {}, false
	}
	channels: [3]u8
	for i in 0..<3 {
		index := i
		if len(digits) == 6 {
			index *= 2
		}
		high, ok := grid_hex_digit(digits[index])
		if !ok {
			return {}, false
		}
		if len(digits) == 3 {
			channels[i] = high * 17
		} else {
			low, valid := grid_hex_digit(digits[index+1])
			if !valid {
				return {}, false
			}
			channels[i] = (high << 4) | low
		}
	}
	return rgb(channels[0], channels[1], channels[2]), true
}

@(private)
grid_hex_digit :: proc(c: byte) -> (u8, bool) {
	if c >= '0' && c <= '9' {
		return c-'0', true
	}
	if c >= 'a' && c <= 'f' {
		return c-'a'+10, true
	}
	if c >= 'A' && c <= 'F' {
		return c-'A'+10, true
	}
	return 0, false
}

// Attribute is a cell style flag; backends decide how to render it.
Attribute :: enum {
	Bold,
	Italic,
	Underline,
	Reverse,
	Dim,
	Blink,
	Hidden,
	Strikethrough,
}

Style :: struct {
	fg, bg:     Color,
	attributes: bit_set[Attribute; u8],
}

// A glyph occupies one logical cell, not necessarily one terminal column.
// Backends must sanitize controls and invalid runes and handle glyph widths.
Cell :: struct {
	glyph: rune,
	style: Style,
}

BLANK_CELL :: Cell{glyph = ' '}

// Rect uses cell coordinates and half-open, non-negative extents.
Rect :: struct {
	x, y:          int,
	width, height: int,
}

Grid_Error :: enum {
	None,
	Invalid_Dimensions,
	Allocation_Failed,
}

@(private)
Dirty_Row :: struct {
	start, end: int, // Half-open; equal bounds mean the row is clean.
}

// MAX_CLIP_DEPTH is the maximum number of nested clips.
MAX_CLIP_DEPTH :: 16

// Grid owns its buffers. Do not copy it or modify its fields directly.
Grid :: struct {
	width, height:          int,
	allocator:              runtime.Allocator,
	cells:                  []Cell,
	presented:              []Cell,
	dirty:                  []Dirty_Row,
	dirty_start, dirty_end: int,
	presented_valid:        bool,
	clips:                  [MAX_CLIP_DEPTH]Rect,
	clip_depth:             int,
}

// grid_init creates a blank grid. The allocator must outlive the grid.
grid_init :: proc(width, height: int, allocator := context.allocator) -> (Grid, Grid_Error) {
	grid := Grid{allocator = allocator}
	err := grid_resize(&grid, width, height)
	return grid, err
}

// grid_destroy releases the grid's buffers and resets its clips; it is safe to call again.
grid_destroy :: proc(grid: ^Grid) {
	if len(grid.cells) > 0 {
		delete(grid.cells, grid.allocator)
		delete(grid.presented, grid.allocator)
		delete(grid.dirty, grid.allocator)
	}
	grid^ = {}
}

// grid_bounds returns the grid's dimensions as a rectangle at the origin.
grid_bounds :: proc(grid: ^Grid) -> Rect {
	return {0, 0, grid.width, grid.height}
}

// grid_resize preserves the overlapping cells and blanks newly exposed cells.
// On error the grid is unchanged. The host/backend handles size changes,
// including clearing any former viewport outside a smaller grid.
// Clips remain in grid coordinates and are intersected with the current bounds.
grid_resize :: proc(grid: ^Grid, width, height: int) -> Grid_Error {
	if width < 0 || height < 0 {
		return .Invalid_Dimensions
	}
	if width == grid.width && height == grid.height {
		return .None
	}

	cells, presented: []Cell
	dirty: []Dirty_Row
	if width > 0 && height > 0 {
		if width > max(int) / height {
			return .Invalid_Dimensions
		}
		count := width * height
		if count > max(int) / size_of(Cell) || height > max(int) / size_of(Dirty_Row) {
			return .Invalid_Dimensions
		}

		err: runtime.Allocator_Error
		cells, err = make([]Cell, count, grid.allocator)
		if err != nil {
			return .Allocation_Failed
		}
		presented, err = make([]Cell, count, grid.allocator)
		if err != nil {
			delete(cells, grid.allocator)
			return .Allocation_Failed
		}
		dirty, err = make([]Dirty_Row, height, grid.allocator)
		if err != nil {
			delete(cells, grid.allocator)
			delete(presented, grid.allocator)
			return .Allocation_Failed
		}

		for &cell in cells {
			cell = BLANK_CELL
		}
		if len(grid.cells) > 0 {
			for y in 0..<min(height, grid.height) {
				copy(cells[y*width:][:min(width, grid.width)],
				     grid.cells[y*grid.width:][:min(width, grid.width)])
			}
		}
		for &row in dirty {
			row = {0, width}
		}
	}

	if len(grid.cells) > 0 {
		delete(grid.cells, grid.allocator)
		delete(grid.presented, grid.allocator)
		delete(grid.dirty, grid.allocator)
	}
	grid.width, grid.height = width, height
	grid.cells, grid.presented, grid.dirty = cells, presented, dirty
	grid.dirty_start = 0
	grid.dirty_end = len(dirty)
	grid.presented_valid = false
	return .None
}

// get_cell returns false for coordinates outside the grid.
get_cell :: proc(grid: ^Grid, x, y: int) -> (Cell, bool) {
	if x < 0 || y < 0 || x >= grid.width || y >= grid.height {
		return {}, false
	}
	return grid.cells[y*grid.width+x], true
}

// push_clip intersects rect with the preceding clip; it fails if the stack is full.
// Clips are stored independently of grid bounds so resizing can expose them again.
push_clip :: proc(grid: ^Grid, rect: Rect) -> bool {
	if grid.clip_depth == MAX_CLIP_DEPTH {
		return false
	}
	effective := rect_intersect(rect, rect)
	if grid.clip_depth > 0 {
		effective = rect_intersect(grid.clips[grid.clip_depth-1], effective)
	}
	grid.clips[grid.clip_depth] = effective
	grid.clip_depth += 1
	return true
}

// pop_clip removes the most recent clip, or does nothing if the stack is empty.
pop_clip :: proc(grid: ^Grid) {
	if grid.clip_depth > 0 {
		grid.clip_depth -= 1
	}
}

// current_clip returns the effective clip intersected with current grid bounds.
current_clip :: proc(grid: ^Grid) -> Rect {
	if grid.clip_depth == 0 {
		return grid_bounds(grid)
	}
	return rect_intersect(grid.clips[grid.clip_depth-1], grid_bounds(grid))
}

// clip_scope pushes a clip and automatically pops it at the end of the scope
// containing the call, but only if the push succeeded.
@(deferred_in_out=clip_scope_end)
clip_scope :: proc(grid: ^Grid, rect: Rect) -> bool {
	return push_clip(grid, rect)
}

@(private)
clip_scope_end :: proc(grid: ^Grid, rect: Rect, pushed: bool) {
	if pushed {
		pop_clip(grid)
	}
}

// set_cell returns false for coordinates outside the grid or current clip.
set_cell :: proc(grid: ^Grid, x, y: int, cell: Cell) -> bool {
	if !rect_contains(current_clip(grid), x, y) {
		return false
	}
	index := y*grid.width + x
	if grid.cells[index] != cell {
		grid.cells[index] = cell
		grid_mark_dirty(grid, y, x, x+1)
	}
	return true
}

@(private)
grid_mark_dirty :: proc(grid: ^Grid, y, start, end: int) {
	row := &grid.dirty[y]
	if row.start == row.end {
		row.start, row.end = start, end
	} else {
		row.start = min(row.start, start)
		row.end = max(row.end, end)
	}
	if grid.dirty_start == grid.dirty_end {
		grid.dirty_start, grid.dirty_end = y, y+1
	} else {
		grid.dirty_start = min(grid.dirty_start, y)
		grid.dirty_end = max(grid.dirty_end, y+1)
	}
}

// draw_text draws one decoded rune per cell on one row, including controls.
// It clips to the current clip and grid; backends handle sanitization and widths.
draw_text :: proc(grid: ^Grid, x, y: int, text: string, style: Style = {}) {
	clip := current_clip(grid)
	if rect_is_empty(clip) || y < clip.y || y >= clip.y+clip.height ||
	   x >= clip.x+clip.width {
		return
	}
	column := x
	for glyph in text {
		if column >= clip.x+clip.width {
			break
		}
		if column >= clip.x {
			set_cell(grid, column, y, {glyph, style})
		}
		column += 1
	}
}

// fill clips a rectangle to the current clip and grid. Non-positive sizes do nothing.
fill :: proc(grid: ^Grid, x, y, width, height: int, cell: Cell) {
	if len(grid.cells) == 0 {
		return
	}
	area := rect_intersect(Rect{x, y, width, height}, current_clip(grid))
	if rect_is_empty(area) {
		return
	}
	for row_y in area.y..<area.y+area.height {
		start, end := area.x+area.width, area.x
		offset := row_y * grid.width
		for column_x in area.x..<area.x+area.width {
			if grid.cells[offset+column_x] != cell {
				grid.cells[offset+column_x] = cell
				start = min(start, column_x)
				end = column_x+1
			}
		}
		if start < end {
			grid_mark_dirty(grid, row_y, start, end)
		}
	}
}
