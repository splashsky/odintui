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

Attribute :: enum {
	Bold,
	Italic,
	Underline,
	Reverse,
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

// Grid owns its buffers. Do not copy it or modify its fields directly.
Grid :: struct {
	width, height:          int,
	allocator:              runtime.Allocator,
	cells:                  []Cell,
	presented:              []Cell,
	dirty:                  []Dirty_Row,
	dirty_start, dirty_end: int,
	presented_valid:        bool,
}

// grid_init creates a blank grid. The allocator must outlive the grid.
grid_init :: proc(width, height: int, allocator := context.allocator) -> (Grid, Grid_Error) {
	grid := Grid{allocator = allocator}
	err := grid_resize(&grid, width, height)
	return grid, err
}

// grid_destroy releases the grid's buffers; it is safe to call again.
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

// set_cell returns false for coordinates outside the grid.
set_cell :: proc(grid: ^Grid, x, y: int, cell: Cell) -> bool {
	if x < 0 || y < 0 || x >= grid.width || y >= grid.height {
		return false
	}
	index := y*grid.width + x
	if grid.cells[index] != cell {
		grid.cells[index] = cell
		row := &grid.dirty[y]
		if row.start == row.end {
			row.start, row.end = x, x+1
		} else {
			row.start = min(row.start, x)
			row.end = max(row.end, x+1)
		}
		if grid.dirty_start == grid.dirty_end {
			grid.dirty_start, grid.dirty_end = y, y+1
		} else {
			grid.dirty_start = min(grid.dirty_start, y)
			grid.dirty_end = max(grid.dirty_end, y+1)
		}
	}
	return true
}

// draw_text draws one decoded rune per cell on one row, including controls.
// It clips at the grid edges; backends handle sanitization and glyph widths.
draw_text :: proc(grid: ^Grid, x, y: int, text: string, style: Style = {}) {
	if y < 0 || y >= grid.height || grid.width == 0 || x >= grid.width {
		return
	}
	column := x
	for glyph in text {
		if column >= grid.width {
			break
		}
		if column >= 0 {
			set_cell(grid, column, y, {glyph, style})
		}
		column += 1
	}
}

// fill clips a rectangle to the grid. Non-positive dimensions do nothing.
fill :: proc(grid: ^Grid, x, y, width, height: int, cell: Cell) {
	if len(grid.cells) == 0 || width <= 0 || height <= 0 || x >= grid.width || y >= grid.height {
		return
	}
	x, y, width, height := x, y, width, height
	if x < 0 {
		if x <= -width {
			return
		}
		width += x
		x = 0
	}
	if y < 0 {
		if y <= -height {
			return
		}
		height += y
		y = 0
	}
	width = min(width, grid.width-x)
	height = min(height, grid.height-y)
	for row in y..<y+height {
		for column in x..<x+width {
			set_cell(grid, column, row, cell)
		}
	}
}
