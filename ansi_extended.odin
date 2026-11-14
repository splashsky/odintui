package odintui

// Ansi_Extended_Backend borrows an ordinary ANSI backend and, optionally, a
// Link_Grid. The zero value has no backend and cannot render; synchronized
// output and hyperlinks are opt-in. Do not copy or mutate it during a frame.
// Use render_linked with links or render without them. Never use the underlying
// backend concurrently, and call immediate ANSI helpers only between frames.
Ansi_Extended_Backend :: struct {
	ansi: ^Ansi_Backend,
	links: ^Link_Grid,
	synchronized_output: bool,
	frame_started, sync_open, link_open, frame_link_used: bool,
	recover_sync, recover_link: bool,
	active_link: u32,
}

// ansi_extended_backend returns callbacks borrowing the extension state.
ansi_extended_backend :: proc(state: ^Ansi_Extended_Backend) -> Backend {
	return {state, ansi_extended_draw, ansi_extended_flush}
}

@(private)
ansi_extended_fail :: proc(ext: ^Ansi_Extended_Backend) {
	ext.recover_sync = ext.recover_sync || ext.sync_open
	ext.recover_link = ext.recover_link || ext.link_open || ext.frame_link_used
	ext.frame_started, ext.sync_open, ext.link_open, ext.frame_link_used = false, false, false, false
	ext.active_link = 0
	if ext.ansi != nil && !ext.ansi.cancel { ansi_fail(ext.ansi) }
}

// ansi_extended_recover cancels an interrupted/abandoned frame, closes any
// possibly open OSC 8 link and ends DEC synchronized output. Call this before
// leaving the terminal after a failure, or before abandoning an unfinished
// frame. A successful retry through render also performs recovery automatically.
ansi_extended_recover :: proc(ext: ^Ansi_Extended_Backend) -> bool {
	if ext == nil || ext.ansi == nil { return false }
	if ext.frame_started { ansi_extended_fail(ext) }
	state := ext.ansi
	ansi_prepare(state)
	if !ansi_reserve(state, 32) { return false }
	if ext.recover_link { ansi_append(state, "\x1b]8;;\x1b\\") }
	if ext.recover_sync { ansi_append(state, "\x1b[?2026l") }
	if !ansi_drain(state) { return false }
	ext.recover_link, ext.recover_sync = false, false
	return true
}

@(private)
ansi_extended_draw :: proc(data: rawptr, x, y: int, cells: []Cell) -> bool {
	ext := (^Ansi_Extended_Backend)(data)
	if ext == nil || ext.ansi == nil { return false }
	state := ext.ansi
	if x < 0 || y < 0 || x == max(int) || y == max(int) || len(cells) > max(int)-x ||
	   (ext.links != nil && (!link_grid_valid(ext.links, ext.links.grid) ||
	    y >= ext.links.height || x > ext.links.width || len(cells) > ext.links.width-x)) {
		ansi_extended_fail(ext)
		return false
	}
	if len(cells) == 0 { return true }
	ansi_prepare(state)
	if !ansi_reserve(state, 128) { ansi_extended_fail(ext); return false }
	if !ext.frame_started {
		if ext.recover_link { ansi_append(state, "\x1b]8;;\x1b\\") }
		if ext.recover_sync { ansi_append(state, "\x1b[?2026l") }
		ext.frame_started = true
		if ext.synchronized_output {
			ext.sync_open = true
			ansi_append(state, "\x1b[?2026h")
		}
	}
	if !state.cursor_known || state.cursor_x != x || state.cursor_y != y { ansi_move(state, x, y) }
	for i := 0; i < len(cells); {
		id: u32
		if ext.links != nil {
			id = ext.links.current[y*ext.links.width+x+i]
			if u64(id) > u64(len(ext.links.urls)) { id = 0 }
		}
		if id != ext.active_link {
			if !ansi_reserve(state, 128) { ansi_extended_fail(ext); return false }
			if ext.link_open {
				ansi_append(state, "\x1b]8;;\x1b\\")
				ext.link_open = false
			}
			ext.active_link = id
			if id != 0 {
				ext.link_open, ext.frame_link_used = true, true
				ansi_append(state, "\x1b]8;;")
				if !ansi_sanitized(state, ext.links.urls[id-1]) || !ansi_reserve(state, 128) {
					ansi_extended_fail(ext)
					return false
				}
				ansi_append(state, "\x1b\\")
			}
		}
		end := i+1
		if ext.links != nil {
			for end < len(cells) {
				next := ext.links.current[y*ext.links.width+x+end]
				if u64(next) > u64(len(ext.links.urls)) { next = 0 }
				if next != id && cells[end].glyph != CONTINUATION { break }
				end += 1
			}
		} else {
			end = len(cells)
		}
		if !ansi_draw_run(state, x+i, y, cells[i:end]) {
			ansi_extended_fail(ext)
			return false
		}
		i = end
	}
	return true
}

@(private)
ansi_extended_flush :: proc(data: rawptr) -> bool {
	ext := (^Ansi_Extended_Backend)(data)
	if ext == nil || ext.ansi == nil { return false }
	state := ext.ansi
	ansi_prepare(state)
	if !ansi_reserve(state, 32) { ansi_extended_fail(ext); return false }
	if ext.link_open { ansi_append(state, "\x1b]8;;\x1b\\") }
	ansi_append(state, "\x1b[0m")
	if ext.sync_open { ansi_append(state, "\x1b[?2026l") }
	if !ansi_drain(state) { ansi_extended_fail(ext); return false }
	state.cursor_known, state.style_known = false, false
	ext.frame_started, ext.sync_open, ext.link_open, ext.frame_link_used = false, false, false, false
	ext.recover_sync, ext.recover_link = false, false
	ext.active_link = 0
	return true
}
