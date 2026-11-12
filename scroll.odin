package odintui

// scroll_clamp clamps offset to the valid range for content and viewport.
// Negative content, viewport, and offset are treated as zero.
scroll_clamp :: proc(offset, content, viewport: int) -> int {
	total := max(content, 0)
	view := max(viewport, 0)
	return clamp(offset, 0, max(total-view, 0))
}

// scroll_into_view moves offset minimally to expose [start, start+size).
// Negative arguments are zero; an empty item leaves the offset unchanged.
// An item larger than the viewport, including a zero viewport, aligns its
// start. Results exceeding max(int) saturate there.
scroll_into_view :: proc(offset, start, size, viewport: int) -> int {
	current := max(offset, 0)
	first := max(start, 0)
	length := max(size, 0)
	view := max(viewport, 0)
	if length == 0 {
		return current
	}
	if length > view || first < current {
		return first
	}
	end := i128(first) + i128(length)
	if end > i128(current)+i128(view) {
		return int(min(end-i128(view), i128(max(int))))
	}
	return current
}

// Scrollbar_Options controls track and thumb cells. Zero glyphs select a
// horizontal or vertical line for the track and a full block for the thumb.
Scrollbar_Options :: struct {
	track, thumb:             rune,
	track_style, thumb_style: Style,
	always_show:              bool,
}

// draw_scrollbar draws on the first row or column of bounds. The thumb is
// proportional to viewport/content, at least one cell, and reaches both ends.
// Non-positive sizes draw nothing; otherwise an unscrollable track is hidden
// unless always_show is set. Negative content and viewport are zero.
draw_scrollbar :: proc(
	grid: ^Grid, bounds: Rect, axis: Layout_Axis, content, viewport, offset: int,
	options: Scrollbar_Options = {},
) {
	length := scroll_length(bounds, axis)
	total := max(content, 0)
	view := max(viewport, 0)
	if length == 0 || (total <= view && !options.always_show) {
		return
	}
	thumb := scroll_thumb_length(length, total, view)
	travel := length-thumb
	maximum := scroll_clamp(max(int), total, view)
	position := scroll_scale(scroll_clamp(offset, total, view), maximum, travel)
	track_glyph := options.track
	if track_glyph == 0 {
		track_glyph = '─'
		if axis == .Column {
			track_glyph = '│'
		}
	}
	thumb_glyph := options.thumb
	if thumb_glyph == 0 {
		thumb_glyph = '█'
	}
	scroll_fill(grid, bounds, axis, 0, length, {track_glyph, options.track_style})
	scroll_fill(grid, bounds, axis, position, thumb, {thumb_glyph, options.thumb_style})
}

// scrollbar_offset_at maps a cell on the drawn track to an offset, centering
// the thumb on the cell and clamping at the ends. It returns false for cells
// off the track or unscrollable content. A one-cell track maps to zero.
scrollbar_offset_at :: proc(
	bounds: Rect, axis: Layout_Axis, content, viewport, x, y: int,
) -> (offset: int, ok: bool) {
	length := scroll_length(bounds, axis)
	total := max(content, 0)
	view := max(viewport, 0)
	if length == 0 || total <= view || !rect_contains(bounds, x, y) {
		return 0, false
	}
	index: int
	if axis == .Column {
		if x != bounds.x {
			return 0, false
		}
		index = int(i128(y)-i128(bounds.y))
	} else {
		if y != bounds.y {
			return 0, false
		}
		index = int(i128(x)-i128(bounds.x))
	}
	thumb := scroll_thumb_length(length, total, view)
	travel := length-thumb
	position := clamp(index-thumb/2, 0, travel)
	return scroll_scale(position, travel, total-view), true
}

// Slider_Options controls track and thumb cells. Zero glyphs select a line
// matching the axis and a circular thumb.
Slider_Options :: struct {
	track, thumb:             rune,
	track_style, thumb_style: Style,
}

// draw_slider draws on the first row or column of bounds. Values clamp to
// [0, 1], NaN is zero, and positions round to the nearest cell, with ties
// toward the end. Extremely long tracks are limited by f64 precision.
draw_slider :: proc(
	grid: ^Grid, bounds: Rect, axis: Layout_Axis, value: f64,
	options: Slider_Options = {},
) {
	length := scroll_length(bounds, axis)
	if length == 0 {
		return
	}
	position := 0
	if value >= 1 {
		position = length-1
	} else if value > 0 {
		position = scroll_slider_position(length-1, value)
	}
	track := options.track
	if track == 0 {
		track = '─'
		if axis == .Column {
			track = '│'
		}
	}
	thumb := options.thumb
	if thumb == 0 {
		thumb = '●'
	}
	scroll_fill(grid, bounds, axis, 0, length, {track, options.track_style})
	scroll_fill(grid, bounds, axis, position, 1, {thumb, options.thumb_style})
}

// slider_value_at maps a cell on the first row or column of bounds to its
// normalized value. It returns false off the track; a one-cell track maps to
// zero. Tracks up to 2^53+1 cells round-trip through draw_slider. Longer
// tracks may have adjacent cells that f64 cannot distinguish.
slider_value_at :: proc(
	bounds: Rect, axis: Layout_Axis, x, y: int,
) -> (value: f64, ok: bool) {
	length := scroll_length(bounds, axis)
	if length == 0 || !rect_contains(bounds, x, y) {
		return 0, false
	}
	index: int
	if axis == .Column {
		if x != bounds.x {
			return 0, false
		}
		index = int(i128(y)-i128(bounds.y))
	} else {
		if y != bounds.y {
			return 0, false
		}
		index = int(i128(x)-i128(bounds.x))
	}
	if length == 1 {
		return 0, true
	}
	return f64(index)/f64(length-1), true
}

@(private)
scroll_slider_position :: proc(travel: int, value: f64) -> int {
	// Compute the rounded product exactly to avoid float-to-int overflow.
	bits := transmute(u64)value
	exponent := int((bits >> 52) & 0x7ff)
	if exponent == 0 {
		return 0
	}
	shift := 1075-exponent
	if shift >= 128 {
		return 0
	}
	significand := (bits & 0x000f_ffff_ffff_ffff) | (u64(1) << 52)
	product := u128(travel)*u128(significand)
	return int((product+(u128(1) << uint(shift-1))) >> uint(shift))
}

@(private)
scroll_length :: proc(bounds: Rect, axis: Layout_Axis) -> int {
	if rect_is_empty(bounds) {
		return 0
	}
	if axis == .Column {
		return bounds.height
	}
	return bounds.width
}

@(private)
scroll_thumb_length :: proc(length, content, viewport: int) -> int {
	if content <= 0 || content <= viewport {
		return length
	}
	return max(1, int(u128(length)*u128(viewport)/u128(content)))
}

@(private)
scroll_scale :: proc(value, source, target: int) -> int {
	if source <= 0 || target <= 0 {
		return 0
	}
	return int((u128(value)*u128(target)+u128(source/2))/u128(source))
}

@(private)
scroll_fill :: proc(grid: ^Grid, bounds: Rect, axis: Layout_Axis, start, length: int, cell: Cell) {
	if length <= 0 {
		return
	}
	if axis == .Column {
		y := i128(bounds.y)+i128(start)
		if y <= i128(max(int)) {
			fill(grid, bounds.x, int(y), 1, length, cell)
		}
	} else {
		x := i128(bounds.x)+i128(start)
		if x <= i128(max(int)) {
			fill(grid, int(x), bounds.y, length, 1, cell)
		}
	}
}
