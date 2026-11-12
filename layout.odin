package odintui

// Constraint_Kind selects a fixed, percentage, or weighted fill length.
Constraint_Kind :: enum {
	Fill,
	Fixed,
	Percent,
}

// Constraint describes a split length. The zero value is an unconstrained
// fill of weight 1. Fill's max_size of zero means no maximum.
Constraint :: struct {
	kind:     Constraint_Kind,
	value:    int,
	min_size: int,
	max_size: int,
}

// layout_fixed requests an exact number of cells, clipped to available space.
layout_fixed :: proc(size: int) -> Constraint {
	return {kind = .Fixed, value = size}
}

// layout_percent requests an integer percentage of the space after gaps.
layout_percent :: proc(percent: int) -> Constraint {
	return {kind = .Percent, value = percent}
}

// layout_fill shares leftover cells by weight. Non-positive weights use 1;
// min_size is non-negative and max_size <= 0 means no maximum.
layout_fill :: proc(weight: int = 1, min_size: int = 0, max_size: int = 0) -> Constraint {
	return {kind = .Fill, value = weight, min_size = min_size, max_size = max_size}
}

// layout_split writes min(len(constraints), len(out)) rectangles to out.
// Gaps occur between every pair, even empty items, and are clipped to bounds.
// Fixed and percent requests are reserved in order before fills; later requests
// are clipped. Percentages are clamped to 0..100 and rounded down. Fill minima
// are then reserved in order, clipped to their maximum and remaining space.
// Remaining cells are shared by weight above those minima: fills over their
// maximum are capped and the remainder is redistributed, with rounding cells
// given left/top first. Space left after all maxima is unused.
// Negative extents and gaps are zero. Coordinate advancement saturates at
// max(int), discarding any inaccessible remainder, like layout_take.
layout_split :: proc(
	bounds: Rect,
	axis: Layout_Axis,
	constraints: []Constraint,
	out: []Rect,
	gap: int = 0,
) -> []Rect {
	count := min(len(constraints), len(out))
	rects := out[:count]
	if count == 0 {
		return rects
	}

	cursor := layout_init(bounds, axis)
	space := cursor.remaining.width
	if axis == .Column {
		space = cursor.remaining.height
	}
	spacing := max(gap, 0)
	gaps := min(u128(space), u128(spacing) * u128(count-1))
	available := space - int(gaps)
	left := available

	for constraint, i in constraints[:count] {
		rects[i] = {}
		size := 0
		switch constraint.kind {
		case .Fixed:
			size = max(constraint.value, 0)
		case .Percent:
			p := clamp(constraint.value, 0, 100)
			size = int(u128(available) * u128(p) / 100)
		case .Fill:
		}
		size = min(size, left)
		rects[i].width = size
		left -= size
	}

	for constraint, i in constraints[:count] {
		if constraint.kind != .Fill {
			continue
		}
		minimum := min(max(constraint.min_size, 0), layout_fill_limit(constraint))
		size := min(minimum, left)
		rects[i].width = size
		left -= size
	}

	for left > 0 {
		total_weight: u128
		for constraint, i in constraints[:count] {
			if constraint.kind == .Fill && rects[i].width < layout_fill_limit(constraint) {
				total_weight += u128(max(constraint.value, 1))
			}
		}
		if total_weight == 0 {
			break
		}

		pool := left
		capped := false
		for constraint, i in constraints[:count] {
			if constraint.kind != .Fill {
				continue
			}
			capacity := layout_fill_limit(constraint) - rects[i].width
			if capacity <= 0 {
				continue
			}
			share := int(u128(pool) * u128(max(constraint.value, 1)) / total_weight)
			if share > capacity {
				rects[i].width += capacity
				left -= capacity
				capped = true
			}
		}
		if capped {
			continue
		}

		for constraint, i in constraints[:count] {
			if constraint.kind == .Fill && rects[i].width < layout_fill_limit(constraint) {
				share := int(u128(pool) * u128(max(constraint.value, 1)) / total_weight)
				rects[i].width += share
				left -= share
			}
		}
		for constraint, i in constraints[:count] {
			if left == 0 {
				break
			}
			if constraint.kind == .Fill && rects[i].width < layout_fill_limit(constraint) {
				rects[i].width += 1
				left -= 1
			}
		}
	}

	for &rect, i in rects {
		size := rect.width
		rect = cursor.remaining
		if axis == .Row {
			rect.width = min(size, cursor.remaining.width)
			layout_advance(&cursor.remaining.x, &cursor.remaining.width, rect.width)
			if i+1 < count {
				layout_advance(&cursor.remaining.x, &cursor.remaining.width, min(spacing, cursor.remaining.width))
			}
		} else {
			rect.height = min(size, cursor.remaining.height)
			layout_advance(&cursor.remaining.y, &cursor.remaining.height, rect.height)
			if i+1 < count {
				layout_advance(&cursor.remaining.y, &cursor.remaining.height, min(spacing, cursor.remaining.height))
			}
		}
	}
	return rects
}

// layout_split_n is the fixed-array form of layout_split.
layout_split_n :: proc(
	bounds: Rect,
	axis: Layout_Axis,
	constraints: [$N]Constraint,
	gap: int = 0,
) -> [N]Rect {
	constraints := constraints
	result: [N]Rect
	layout_split(bounds, axis, constraints[:], result[:], gap)
	return result
}

@(private)
layout_fill_limit :: proc(constraint: Constraint) -> int {
	if constraint.max_size <= 0 {
		return max(int)
	}
	return constraint.max_size
}

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

// layout_take_end takes from the right or bottom, consuming the preceding gap.
// Non-positive sizes and empty bounds do not advance the cursor. Coordinates
// beyond max(int) are inaccessible and are discarded before a positive take.
layout_take_end :: proc(layout: ^Layout, size: int) -> Rect {
	result := layout.remaining
	if layout.axis == .Row {
		result.x = layout_end_coordinate(result.x, max(result.width, 0))
		result.width = 0
	} else {
		result.y = layout_end_coordinate(result.y, max(result.height, 0))
		result.height = 0
	}
	if size <= 0 || layout.remaining.width <= 0 || layout.remaining.height <= 0 {
		return result
	}

	if layout.axis == .Row {
		origin := layout.remaining.x
		extent := layout.remaining.width
		if origin > max(int)-(extent-1) {
			extent = max(int)-origin+1
		}
		result.width = min(size, extent)
		result.x = origin + (extent - result.width)
		layout.remaining.width = extent - result.width
		layout.remaining.width -= min(max(layout.gap, 0), layout.remaining.width)
	} else {
		origin := layout.remaining.y
		extent := layout.remaining.height
		if origin > max(int)-(extent-1) {
			extent = max(int)-origin+1
		}
		result.height = min(size, extent)
		result.y = origin + (extent - result.height)
		layout.remaining.height = extent - result.height
		layout.remaining.height -= min(max(layout.gap, 0), layout.remaining.height)
	}
	return result
}

// layout_take_rest returns all remaining bounds and exhausts the cursor
// without consuming a gap, even if the other dimension is empty.
layout_take_rest :: proc(layout: ^Layout) -> Rect {
	result := layout.remaining
	if layout.axis == .Row {
		layout_advance(&layout.remaining.x, &layout.remaining.width, layout.remaining.width)
		layout.remaining.width = 0
	} else {
		layout_advance(&layout.remaining.y, &layout.remaining.height, layout.remaining.height)
		layout.remaining.height = 0
	}
	return result
}

@(private)
layout_end_coordinate :: proc(origin, extent: int) -> int {
	if origin > max(int)-extent {
		return max(int)
	}
	return origin + extent
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
