package odintui

// Link_Grid is an optional sidecar with caller-owned per-column link planes
// and borrowed URLs. ID 0 means no link; ID n refers to urls[n-1]. Do not copy
// or mutate its fields while attached. It must not outlive its grid or planes.
Link_Grid :: struct {
	grid: ^Grid,
	current, presented: []u32,
	urls: []string,
	width, height: int,
}

// link_grid_init attaches and clears two non-overlapping planes, each with at
// least width*height entries, and invalidates the grid. Reinitialize after
// every resize. URL contents must remain stable until invalidation.
link_grid_init :: proc(grid: ^Grid, current, presented: []u32, urls: []string) -> (Link_Grid, bool) {
	if grid == nil || len(current) < len(grid.cells) || len(presented) < len(grid.cells) {
		return {}, false
	}
	count := len(grid.cells)
	if count > 0 {
		a, b := uintptr(raw_data(current)), uintptr(raw_data(presented))
		size := uintptr(count)*size_of(u32)
		if (a <= b && b-a < size) || (b < a && a-b < size) { return {}, false }
	}
	for i in 0..<count { current[i], presented[i] = 0, 0 }
	invalidate(grid)
	return {grid, current[:count], presented[:count], urls, grid.width, grid.height}, true
}

@(private)
link_grid_valid :: proc(links: ^Link_Grid, grid: ^Grid) -> bool {
	return links != nil && grid != nil && links.grid == grid &&
	       links.width == grid.width && links.height == grid.height &&
	       len(links.current) == len(grid.cells) && len(links.presented) == len(grid.cells)
}

// link_grid_set annotates columns in bounds and the grid's current clip. If a
// rectangle touches either half of a wide glyph, both halves receive the ID,
// even across a clip boundary. Annotations persist independently of drawing.
link_grid_set :: proc(links: ^Link_Grid, bounds: Rect, id: u32) -> bool {
	if links == nil || !link_grid_valid(links, links.grid) || u64(id) > u64(len(links.urls)) {
		return false
	}
	grid := links.grid
	area := rect_intersect(bounds, current_clip(grid))
	for y in area.y..<area.y+area.height {
		for x in area.x..<area.x+area.width {
			index := y*grid.width+x
			first, last := x, x+1
			if grid.cells[index].glyph == CONTINUATION && x > 0 { first -= 1 }
			if x+1 < grid.width && grid.cells[index+1].glyph == CONTINUATION { last += 1 }
			for column in first..<last {
				j := y*grid.width+column
				if links.current[j] != id {
					links.current[j] = id
					grid_mark_dirty(grid, y, column, column+1)
				}
			}
		}
	}
	return true
}

// link_grid_destroy detaches the sidecar (but does not free borrowed storage).
// Switching back to render without links requires a complete redraw.
link_grid_destroy :: proc(links: ^Link_Grid) {
	if links == nil { return }
	if links.grid != nil { invalidate(links.grid) }
	links^ = {}
}

// A newly drawn wide glyph can cover columns previously having different link
// IDs. Its second column inherits its first, before links are diffed.
@(private)
link_grid_normalize :: proc(links: ^Link_Grid) {
	grid := links.grid
	for row, i in grid.dirty[grid.dirty_start:grid.dirty_end] {
		y := grid.dirty_start+i
		if row.start == row.end { continue }
		start := max(row.start-1, 0)
		end := min(row.end+1, grid.width)
		for x in start..<end {
			index := y*grid.width+x
			if x > 0 && grid.cells[index].glyph == CONTINUATION &&
			   links.current[index] != links.current[index-1] {
				links.current[index] = links.current[index-1]
				grid_mark_dirty(grid, y, x-1, x+1)
			}
		}
	}
}
