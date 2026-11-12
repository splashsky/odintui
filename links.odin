package odintui

// grid_enable_links attaches caller-owned planes and URL table. Each plane
// needs width*height entries and must not overlap. ID 0 means no link; ID n
// refers to urls[n-1]. The planes are cleared. They and the URL strings must
// outlive the attachment. Resize detaches them; reattach after resize.
// Changing URL contents requires invalidate. The table must not be modified
// during render. Link annotations persist independently of cell drawing.
grid_enable_links :: proc(grid: ^Grid, current, presented: []u32, urls: []string) -> bool {
	if grid == nil || len(current) < len(grid.cells) || len(presented) < len(grid.cells) {
		return false
	}
	count := len(grid.cells)
	if count > 0 {
		a, b := uintptr(raw_data(current)), uintptr(raw_data(presented))
		size := uintptr(count)*size_of(u32)
		if (a <= b && b-a < size) || (b < a && a-b < size) { return false }
	}
	grid.links, grid.presented_links = current[:count], presented[:count]
	grid.link_urls = urls
	for i in 0..<count {
		grid.links[i], grid.presented_links[i] = 0, 0
	}
	invalidate(grid)
	return true
}

// grid_link_rect annotates columns in bounds and the current clip, without
// allocating. If a rectangle touches either half of a wide glyph, both halves
// receive the same ID, even across a clip boundary. Returns false for a
// detached plane or an ID not in the table.
grid_link_rect :: proc(grid: ^Grid, bounds: Rect, id: u32) -> bool {
	if grid == nil || len(grid.links) != len(grid.cells) ||
	   (len(grid.cells) > 0 && raw_data(grid.links) == nil) || u64(id) > u64(len(grid.link_urls)) {
		return false
	}
	area := rect_intersect(bounds, current_clip(grid))
	for y in area.y..<area.y+area.height {
		for x in area.x..<area.x+area.width {
			index := y*grid.width+x
			first, last := x, x+1
			if grid.cells[index].glyph == CONTINUATION && x > 0 { first -= 1 }
			if x+1 < grid.width && grid.cells[index+1].glyph == CONTINUATION { last += 1 }
			for column in first..<last {
				j := y*grid.width+column
				if grid.links[j] != id {
					grid.links[j] = id
					grid_mark_dirty(grid, y, column, column+1)
				}
			}
		}
	}
	return true
}

// grid_disable_links detaches the planes and forces a complete redraw.
grid_disable_links :: proc(grid: ^Grid) {
	if grid == nil { return }
	grid.links, grid.presented_links, grid.link_urls = nil, nil, nil
	invalidate(grid)
}
