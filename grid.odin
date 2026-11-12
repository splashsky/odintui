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

// A cell is one terminal column; CONTINUATION represents a wide glyph's second
// column. Backends must sanitize controls and invalid runes.
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
	clip:                   Rect, // Top clip intersected with bounds; cached for set_cell.
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
				// Shrinking may sever a wide glyph at the right edge.
				if width < grid.width && width > 0 &&
				   grid.cells[y*grid.width+width].glyph == CONTINUATION {
					cells[y*width+width-1].glyph = ' '
				}
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
	grid_update_clip(grid)
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
	grid_update_clip(grid)
	return true
}

// pop_clip removes the most recent clip, or does nothing if the stack is empty.
pop_clip :: proc(grid: ^Grid) {
	if grid.clip_depth > 0 {
		grid.clip_depth -= 1
		grid_update_clip(grid)
	}
}

// current_clip returns the effective clip intersected with current grid bounds.
current_clip :: proc(grid: ^Grid) -> Rect {
	return grid.clip
}

@(private)
grid_update_clip :: proc(grid: ^Grid) {
	grid.clip = grid_bounds(grid)
	if grid.clip_depth > 0 {
		grid.clip = rect_intersect(grid.clips[grid.clip_depth-1], grid.clip)
	}
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

// set_cell draws a glyph and returns whether its first column is in the clip.
// A clipped half of a wide glyph becomes a styled space. Replacing either
// column of an existing wide glyph also clears its other column, even outside
// the clip, to avoid leaving an invalid half-glyph.
set_cell :: proc(grid: ^Grid, x, y: int, cell: Cell) -> bool {
	clip := grid.clip
	inside := rect_contains(clip, x, y)
	width := rune_width(cell.glyph)
	if cell.glyph == CONTINUATION || width == 0 {
		return inside
	}
	if width == 2 && !inside && x < max(int) && rect_contains(clip, x+1, y) {
		grid_put_single(grid, x+1, y, {' ', cell.style})
		return false
	}
	if !inside {
		return false
	}
	if width == 2 {
		if x+1 >= clip.x+clip.width {
			grid_put_single(grid, x, y, {' ', cell.style})
			return true
		}
		index := y*grid.width+x
		continuation := Cell{CONTINUATION, cell.style}
		if grid.cells[index] == cell && grid.cells[index+1] == continuation {
			return true
		}
		grid_clear_pair(grid, x, y)
		grid_clear_pair(grid, x+1, y)
		grid_put_raw(grid, x, y, cell)
		grid_put_raw(grid, x+1, y, continuation)
		// Even when the continuation is unchanged, it must join the diff run.
		grid_mark_dirty(grid, y, x, x+2)
	} else {
		grid_put_single(grid, x, y, cell)
	}
	return true
}

@(private)
grid_put_raw :: proc(grid: ^Grid, x, y: int, cell: Cell) {
	index := y*grid.width+x
	if grid.cells[index] != cell {
		grid.cells[index] = cell
		grid_mark_dirty(grid, y, x, x+1)
	}
}

@(private)
grid_clear_pair :: proc(grid: ^Grid, x, y: int) {
	index := y*grid.width+x
	cell := grid.cells[index]
	if cell.glyph == CONTINUATION && x > 0 {
		other := grid.cells[index-1]
		other.glyph = ' '
		grid_put_raw(grid, x-1, y, other)
	} else if x+1 < grid.width && grid.cells[index+1].glyph == CONTINUATION {
		other := grid.cells[index+1]
		other.glyph = ' '
		grid_put_raw(grid, x+1, y, other)
	}
}

@(private)
grid_put_single :: proc(grid: ^Grid, x, y: int, cell: Cell) {
	index := y*grid.width+x
	if grid.cells[index] == cell { return }
	grid_clear_pair(grid, x, y)
	grid_put_raw(grid, x, y, cell)
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

// draw_text draws one row in display columns, including controls. Zero-width
// runes are dropped; backends sanitize controls and invalid runes.
draw_text :: proc(grid: ^Grid, x, y: int, text: string, style: Style = {}) {
	clip := current_clip(grid)
	if rect_is_empty(clip) || y < clip.y || y >= clip.y+clip.height ||
	   x >= clip.x+clip.width {
		return
	}
	column := i128(x)
	for glyph in text {
		if column >= i128(clip.x+clip.width) {
			break
		}
		width := rune_width(glyph)
		if width > 0 && column >= i128(min(int)) && column <= i128(max(int)) {
			set_cell(grid, int(column), y, {glyph, style})
		}
		column += i128(width)
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
	glyph_width := rune_width(cell.glyph)
	if glyph_width == 0 || cell.glyph == CONTINUATION { return }
	for row_y in area.y..<area.y+area.height {
		column := area.x
		// A wide fill is tiled relative to the original rectangle.
		if glyph_width == 2 && (i128(column)-i128(x)) % 2 != 0 {
			grid_put_single(grid, column, row_y, {' ', cell.style})
			column += 1
		}
		for column < area.x+area.width {
			if glyph_width == 2 && column+1 >= area.x+area.width {
				grid_put_single(grid, column, row_y, {' ', cell.style})
			} else {
				set_cell(grid, column, row_y, cell)
			}
			column += glyph_width
		}
	}
}
