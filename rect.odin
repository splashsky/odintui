package odintui

// Insets specifies the number of cells removed from each side of a rectangle.
Insets :: struct {
	top, right, bottom, left: int,
}

// Align selects the start, center, or end of an available span.
Align :: enum {
	Start,
	Center,
	End,
}

// rect_is_empty reports whether either extent is non-positive.
rect_is_empty :: proc(r: Rect) -> bool {
	return r.width <= 0 || r.height <= 0
}

// rect_intersect returns the overlap, or zero extents when there is none.
rect_intersect :: proc(a, b: Rect) -> Rect {
	x, y := max(a.x, b.x), max(a.y, b.y)
	if rect_is_empty(a) || rect_is_empty(b) {
		return {x, y, 0, 0}
	}
	right := min(i128(a.x)+i128(a.width), i128(b.x)+i128(b.width))
	bottom := min(i128(a.y)+i128(a.height), i128(b.y)+i128(b.height))
	if right <= i128(x) || bottom <= i128(y) {
		return {x, y, 0, 0}
	}
	return {x, y, int(right-i128(x)), int(bottom-i128(y))}
}

// rect_contains tests a point against the half-open rectangle.
rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return !rect_is_empty(r) &&
	       x >= r.x && y >= r.y &&
	       i128(x) < i128(r.x)+i128(r.width) &&
	       i128(y) < i128(r.y)+i128(r.height)
}

// rect_inset removes a uniform or per-side inset, treating negatives as zero.
// Insets are consumed from the start side first and clipped to the available size.
// If an origin would exceed max(int), it is clamped and that extent becomes zero.
rect_inset :: proc{rect_inset_uniform, rect_inset_sides}

@(private)
rect_inset_uniform :: proc(r: Rect, n: int) -> Rect {
	return rect_inset_sides(r, Insets{n, n, n, n})
}

@(private)
rect_inset_sides :: proc(r: Rect, insets: Insets) -> Rect {
	x, width := rect_inset_span(r.x, r.width, insets.left, insets.right)
	y, height := rect_inset_span(r.y, r.height, insets.top, insets.bottom)
	return {x, y, width, height}
}

@(private)
rect_inset_span :: proc(origin, extent, before, after: int) -> (int, int) {
	remaining := max(extent, 0)
	start := min(max(before, 0), remaining)
	remaining -= start
	remaining -= min(max(after, 0), remaining)
	if origin > max(int)-start {
		return max(int), 0
	}
	return origin+start, remaining
}

// rect_align places a clamped size within outer. Center rounds toward start.
// If an origin would exceed max(int), it is clamped and that extent becomes zero.
rect_align :: proc(
	outer: Rect,
	width, height: int,
	horizontal, vertical: Align,
) -> Rect {
	x, result_width := rect_align_span(outer.x, outer.width, width, horizontal)
	y, result_height := rect_align_span(outer.y, outer.height, height, vertical)
	return {x, y, result_width, result_height}
}

@(private)
rect_align_span :: proc(origin, extent, size: int, alignment: Align) -> (int, int) {
	available := max(extent, 0)
	result_size := min(max(size, 0), available)
	offset := 0
	switch alignment {
	case .Start:
	case .Center:
		offset = (available-result_size)/2
	case .End:
		offset = available-result_size
	}
	if origin > max(int)-offset {
		return max(int), 0
	}
	return origin+offset, result_size
}

// rect_center centers a clamped size within outer, rounding toward start.
rect_center :: proc(outer: Rect, width, height: int) -> Rect {
	return rect_align(outer, width, height, .Center, .Center)
}
