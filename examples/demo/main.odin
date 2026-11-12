package main

import tui "../.."
import "core:fmt"
import "core:os"

WIDTH  :: 42
HEIGHT :: 7

// This backend is application-owned. It keeps only printable ASCII cells and
// deliberately ignores styles, so the snapshot is safe to redirect to a file.
Snapshot :: struct {
	cells:      [HEIGHT][WIDTH]byte,
	draw_runs:  int,
	draw_cells: int,
	flushes:    int,
}

snapshot_draw :: proc(data: rawptr, x, y: int, cells: []tui.Cell) -> bool {
	snapshot := (^Snapshot)(data)
	if y < 0 || y >= HEIGHT || x < 0 || x > WIDTH || len(cells) > WIDTH-x {
		return false
	}
	for cell, i in cells {
		glyph := byte('?')
		if cell.glyph >= ' ' && cell.glyph <= '~' {
			glyph = byte(cell.glyph)
		}
		snapshot.cells[y][x+i] = glyph
	}
	snapshot.draw_runs += 1
	snapshot.draw_cells += len(cells)
	return true
}

snapshot_flush :: proc(data: rawptr) -> bool {
	snapshot := (^Snapshot)(data)
	snapshot.flushes += 1
	return true
}

write_text :: proc(text: string) -> bool {
	n, err := os.write(os.stdout, transmute([]byte)text)
	return err == nil && n == len(text)
}

print_frame :: proc(label: string, snapshot: ^Snapshot) -> bool {
	header: [128]byte
	text := fmt.bprintf(
		header[:], "%s: %d draw runs, %d cells, %d flushes\n",
		label, snapshot.draw_runs, snapshot.draw_cells, snapshot.flushes,
	)
	if !write_text(text) {
		return false
	}
	for y in 0..<HEIGHT {
		row := snapshot.cells[y][:]
		n, err := os.write(os.stdout, row)
		if err != nil || n != len(row) || !write_text("\n") {
			return false
		}
	}
	return true
}

run :: proc() -> bool {
	grid, err := tui.grid_init(WIDTH, HEIGHT)
	if err != .None {
		return false
	}
	defer tui.grid_destroy(&grid)

	snapshot: Snapshot
	backend := tui.Backend{&snapshot, snapshot_draw, snapshot_flush}
	border_style := tui.Style{fg = tui.rgb(100, 160, 240)}
	title_style := tui.Style{attributes = {.Bold}}
	filled_style := tui.Style{fg = tui.rgb(40, 200, 120)}
	empty_style := tui.Style{fg = tui.rgb(100, 100, 100)}

	tui.draw_border(&grid, tui.grid_bounds(&grid), border_style)
	content := tui.Rect{2, 1, WIDTH-4, HEIGHT-2}
	layout := tui.layout_init(content, .Column, 1)
	title := tui.layout_take(&layout, 1)
	progress := tui.layout_take(&layout, 1)
	status := tui.layout_take(&layout, 1)
	tui.draw_label(&grid, title, "Odin TUI - upload", title_style)
	tui.draw_progress_bar(&grid, progress, 0.25, filled_style, empty_style)
	tui.draw_label(&grid, status, "Progress: 25%  Input: \x1b界")

	if !tui.render(&grid, backend) || !print_frame("Initial frame", &snapshot) {
		return false
	}

	snapshot.draw_runs, snapshot.draw_cells, snapshot.flushes = 0, 0, 0
	tui.draw_progress_bar(&grid, progress, 0.75, filled_style, empty_style)
	tui.draw_label(&grid, status, "Progress: 75%  Input: \x1b界")
	if !tui.render(&grid, backend) || !print_frame("Updated frame", &snapshot) {
		return false
	}

	snapshot.draw_runs, snapshot.draw_cells, snapshot.flushes = 0, 0, 0
	if !tui.render(&grid, backend) {
		return false
	}
	header: [128]byte
	text := fmt.bprintf(
		header[:], "Unchanged frame: %d draw runs, %d cells, %d flushes\n",
		snapshot.draw_runs, snapshot.draw_cells, snapshot.flushes,
	)
	return write_text(text)
}

main :: proc() {
	if !run() {
		fmt.eprintln("demo: grid, rendering, or output failed")
		os.exit(1)
	}
}
