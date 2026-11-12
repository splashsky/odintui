package odintui

Layout_Axis :: enum {
	Row,
	Column,
}

// Layout is a local cursor over a rectangle. A row consumes widths from the
// left; a column consumes heights from the top. It does not own any storage.
Layout :: struct {
	remaining: Rect,
	axis:      Layout_Axis,
	gap:       int,
}

// layout_init treats negative extents and gaps as zero.
layout_init :: proc(bounds: Rect, axis: Layout_Axis, gap: int = 0) -> Layout {
	bounds := bounds
	bounds.width = max(bounds.width, 0)
	bounds.height = max(bounds.height, 0)
	return {bounds, axis, max(gap, 0)}
}

// layout_remaining returns the unused bounds after chunks and their gaps.
layout_remaining :: proc(layout: ^Layout) -> Rect {
	return layout.remaining
}

// layout_take returns up to size cells along the cursor's axis. A positive
// chunk also consumes the following gap, clipped to the available space.
// Non-positive sizes and empty bounds do not advance the cursor.
layout_take :: proc(layout: ^Layout, size: int) -> Rect {
	result := layout.remaining
	if layout.axis == .Row {
		result.width = 0
	} else {
		result.height = 0
	}
	if size <= 0 || layout.remaining.width <= 0 || layout.remaining.height <= 0 {
		return result
	}

	if layout.axis == .Row {
		result.width = min(size, layout.remaining.width)
		layout_advance(&layout.remaining.x, &layout.remaining.width, result.width)
		layout_advance(&layout.remaining.x, &layout.remaining.width, min(layout.gap, layout.remaining.width))
	} else {
		result.height = min(size, layout.remaining.height)
		layout_advance(&layout.remaining.y, &layout.remaining.height, result.height)
		layout_advance(&layout.remaining.y, &layout.remaining.height, min(layout.gap, layout.remaining.height))
	}
	return result
}

@(private)
layout_advance :: proc(origin, extent: ^int, amount: int) {
	if amount <= 0 {
		return
	}
	// Any remainder beyond the representable coordinate range is inaccessible.
	if origin^ > max(int)-amount {
		origin^ = max(int)
		extent^ = 0
		return
	}
	origin^ += amount
	extent^ -= amount
}
