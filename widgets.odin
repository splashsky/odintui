package odintui

// draw_label draws one rune per cell, clipped to bounds and the grid. A
// carriage return or newline ends the label; other runes are passed through.
draw_label :: proc(grid: ^Grid, bounds: Rect, text: string, style: Style = {}) {
	grid_rect := grid_bounds(grid)
	if bounds.width <= 0 || bounds.height <= 0 || grid_rect.width <= 0 ||
	   bounds.y < 0 || bounds.y >= grid_rect.height || bounds.x >= grid_rect.width {
		return
	}
	x, remaining := bounds.x, bounds.width
	for glyph in text {
		if glyph == '\n' || glyph == '\r' || x >= grid_rect.width {
			break
		}
		if x >= 0 {
			set_cell(grid, x, bounds.y, {glyph, style})
		}
		remaining -= 1
		if remaining == 0 {
			break
		}
		x += 1
	}
}

// draw_border draws the original rectangle's ASCII perimeter. Clipping never
// creates new edges or corners. Corners take precedence for degenerate sizes.
draw_border :: proc(grid: ^Grid, bounds: Rect, style: Style = {}) {
	if bounds.width <= 0 || bounds.height <= 0 {
		return
	}
	right, right_ok := widget_last_coordinate(bounds.x, bounds.width)
	bottom, bottom_ok := widget_last_coordinate(bounds.y, bounds.height)

	fill(grid, bounds.x, bounds.y, bounds.width, 1, {'-', style})
	if bottom_ok {
		fill(grid, bounds.x, bottom, bounds.width, 1, {'-', style})
	}
	fill(grid, bounds.x, bounds.y, 1, bounds.height, {'|', style})
	if right_ok {
		fill(grid, right, bounds.y, 1, bounds.height, {'|', style})
	}
	set_cell(grid, bounds.x, bounds.y, {'+', style})
	if right_ok {
		set_cell(grid, right, bounds.y, {'+', style})
	}
	if bottom_ok {
		set_cell(grid, bounds.x, bottom, {'+', style})
	}
	if right_ok && bottom_ok {
		set_cell(grid, right, bottom, {'+', style})
	}
}

@(private)
widget_last_coordinate :: proc(origin, extent: int) -> (int, bool) {
	offset := extent - 1
	if origin > max(int)-offset {
		return 0, false
	}
	return origin + offset, true
}

// draw_progress_bar paints the entire rectangle with '#' and '-' cells.
// Progress is clamped to [0, 1], NaN is empty, and fractional cells round down.
// Repainting the empty part makes decreasing progress erase the previous fill.
draw_progress_bar :: proc(
	grid: ^Grid,
	bounds: Rect,
	progress: f64,
	filled_style, empty_style: Style,
) {
	if bounds.width <= 0 || bounds.height <= 0 {
		return
	}
	filled := 0
	if progress >= 1 {
		filled = bounds.width
	} else if progress > 0 {
		filled = widget_progress_width(bounds.width, progress)
	}
	fill(grid, bounds.x, bounds.y, bounds.width, bounds.height, {'-', empty_style})
	if filled > 0 {
		fill(grid, bounds.x, bounds.y, filled, bounds.height, {'#', filled_style})
	}
}

@(private)
widget_progress_width :: proc(width: int, progress: f64) -> int {
	// Preserve ordinary floating-point rounding for widths exactly representable
	// as f64; larger widths need integer arithmetic to avoid losing cells.
	if u64(width) <= 1 << 53 {
		return int(f64(width) * progress)
	}
	bits := transmute(u64)progress
	exponent := int((bits >> 52) & 0x7ff)
	if exponent == 0 {
		return 0
	}
	shift := 1075 - exponent
	if shift >= 128 {
		return 0
	}
	significand := (bits & 0x000f_ffff_ffff_ffff) | (u64(1) << 52)
	product := u128(width) * u128(significand)
	return int(product >> uint(shift))
}
