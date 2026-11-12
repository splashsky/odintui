package odintui

import "base:runtime"
import "core:testing"

@(test)
layout_test_split_fixed_array :: proc(t: ^testing.T) {
	parts := layout_split_n(
		Rect{2, 4, 8, 12},
		.Column,
		{layout_fixed(1), layout_fill(), layout_fixed(1)},
		1,
	)
	testing.expect(t, parts == [3]Rect{{2, 4, 8, 1}, {2, 6, 8, 8}, {2, 15, 8, 1}})

	center := layout_split_n(
		Rect{0, 0, 21, 2},
		.Row,
		[3]Constraint{layout_fill(), layout_fixed(10), layout_fill()},
	)
	testing.expect(t, center == [3]Rect{{0, 0, 6, 2}, {6, 0, 10, 2}, {16, 0, 5, 2}})
}

@(test)
layout_test_split_lengths :: proc(t: ^testing.T) {
	constraints := [4]Constraint{layout_fixed(3), layout_percent(25), layout_fill(2), layout_fill()}
	out: [4]Rect
	parts := layout_split(Rect{1, 2, 20, 3}, .Row, constraints[:], out[:], 1)
	testing.expect(t, len(parts) == 4)
	testing.expect(t, out == [4]Rect{{1, 2, 3, 3}, {5, 2, 4, 3}, {10, 2, 7, 3}, {18, 2, 3, 3}})

	short: [2]Rect
	parts = layout_split(Rect{1, 2, 20, 3}, .Row, constraints[:], short[:], 1)
	testing.expect(t, len(parts) == 2 && short == [2]Rect{{1, 2, 3, 3}, {5, 2, 4, 3}})
	testing.expect(t, len(layout_split(Rect{}, .Row, constraints[:0], out[:])) == 0)
	testing.expect(t, len(layout_split(Rect{}, .Row, constraints[:], out[:0])) == 0)

	clipped := [3]Constraint{layout_fill(), layout_percent(80), layout_fixed(8)}
	parts = layout_split(Rect{0, 0, 10, 1}, .Row, clipped[:], out[:])
	testing.expect(t, len(parts) == 3)
	testing.expect(t, parts[0] == Rect{0, 0, 0, 1})
	testing.expect(t, parts[1] == Rect{0, 0, 8, 1})
	testing.expect(t, parts[2] == Rect{8, 0, 2, 1})
}

@(test)
layout_test_split_fill_clamps :: proc(t: ^testing.T) {
	capped := layout_split_n(
		Rect{0, 0, 10, 1},
		.Row,
		[3]Constraint{layout_fill(1, 0, 1), layout_fill(), layout_fill(3)},
	)
	testing.expect(t, capped == [3]Rect{{0, 0, 1, 1}, {1, 0, 3, 1}, {4, 0, 6, 1}})
	minimums := layout_split_n(
		Rect{0, 0, 9, 1},
		.Row,
		[3]Constraint{layout_fill(1, 4, 2), layout_fill(1, 8), layout_fill()},
	)
	testing.expect(t, minimums == [3]Rect{{0, 0, 2, 1}, {2, 0, 7, 1}, {9, 0, 0, 1}})
	all_capped := layout_split_n(
		Rect{0, 0, 20, 1},
		.Row,
		[2]Constraint{layout_fill(1, 0, 3), layout_fill(1, 0, 4)},
	)
	testing.expect(t, all_capped == [2]Rect{{0, 0, 3, 1}, {3, 0, 4, 1}})
	defaults := layout_split_n(Rect{0, 0, 5, 1}, .Row, [2]Constraint{{}, layout_fill(-3, -1, -1)})
	testing.expect(t, defaults == [2]Rect{{0, 0, 3, 1}, {3, 0, 2, 1}})
}

@(test)
layout_test_split_invalid_and_extreme :: proc(t: ^testing.T) {
	parts := layout_split_n(
		Rect{min(int), 2, max(int), 1},
		.Row,
		[3]Constraint{layout_percent(50), layout_fill(max(int)), layout_fill(max(int))},
	)
	half := max(int) / 2
	testing.expect(t, parts[0] == Rect{min(int), 2, half, 1})
	testing.expect(t, parts[1].width == (max(int)-half+1)/2)
	testing.expect(t, parts[2].width == (max(int)-half)/2)
	overflow := layout_split_n(
		Rect{max(int)-1, 0, 8, 1},
		.Row,
		[3]Constraint{layout_fixed(1), layout_fixed(1), layout_fixed(1)},
	)
	testing.expect(t, overflow == [3]Rect{
		{max(int)-1, 0, 1, 1}, {max(int), 0, 1, 1}, {max(int), 0, 0, 1},
	})
	bad := layout_split_n(
		Rect{3, 4, -1, 5},
		.Row,
		[3]Constraint{layout_fixed(-1), layout_percent(max(int)), layout_fill()},
		max(int),
	)
	testing.expect(t, bad == [3]Rect{{3, 4, 0, 5}, {3, 4, 0, 5}, {3, 4, 0, 5}})
	large_gap := layout_split_n(
		Rect{0, 0, 3, 1},
		.Row,
		[3]Constraint{layout_percent(-1), layout_percent(200), layout_fill()},
		max(int),
	)
	testing.expect(t, large_gap == [3]Rect{{0, 0, 0, 1}, {3, 0, 0, 1}, {3, 0, 0, 1}})
}

@(private)
layout_test_allocator_proc :: proc(
	data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int,
	old_memory: rawptr, old_size: int, location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	attempts := (^int)(data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		attempts^ += 1
	}
	return nil, .Out_Of_Memory
}

@(test)
layout_test_split_does_not_allocate :: proc(t: ^testing.T) {
	attempts := 0
	context.allocator = {procedure = layout_test_allocator_proc, data = &attempts}
	parts := layout_split_n(
		Rect{0, 0, 10, 1},
		.Row,
		[3]Constraint{layout_fill(1, 0, 1), layout_fill(), layout_fill(3)},
	)
	cursor := layout_init(Rect{0, 0, 10, 1}, .Row, 1)
	end := layout_take_end(&cursor, 2)
	rest := layout_take_rest(&cursor)
	testing.expect(t, parts[2] == Rect{4, 0, 6, 1})
	testing.expect(t, end == Rect{8, 0, 2, 1} && rest == Rect{0, 0, 7, 1})
	testing.expect(t, attempts == 0)
}

@(test)
layout_test_take_end_and_rest :: proc(t: ^testing.T) {
	cursor := layout_init(Rect{2, 3, 12, 4}, .Row, 2)
	testing.expect(t, layout_take_end(&cursor, 3) == Rect{11, 3, 3, 4})
	testing.expect(t, layout_remaining(&cursor) == Rect{2, 3, 7, 4})
	testing.expect(t, layout_take(&cursor, 2) == Rect{2, 3, 2, 4})
	testing.expect(t, layout_take_end(&cursor, 0) == Rect{9, 3, 0, 4})
	testing.expect(t, layout_take_end(&cursor, -1) == Rect{9, 3, 0, 4})
	testing.expect(t, layout_remaining(&cursor) == Rect{6, 3, 3, 4})
	testing.expect(t, layout_take_rest(&cursor) == Rect{6, 3, 3, 4})
	testing.expect(t, layout_remaining(&cursor) == Rect{9, 3, 0, 4})
	testing.expect(t, layout_take_rest(&cursor) == Rect{9, 3, 0, 4})

	column := layout_init(Rect{-1, 2, 5, 8}, .Column, 1)
	testing.expect(t, layout_take(&column, 1) == Rect{-1, 2, 5, 1})
	testing.expect(t, layout_take_end(&column, 2) == Rect{-1, 8, 5, 2})
	testing.expect(t, layout_take_rest(&column) == Rect{-1, 4, 5, 3})
	testing.expect(t, layout_remaining(&column) == Rect{-1, 7, 5, 0})

	empty := layout_init(Rect{1, 2, 0, 8}, .Column)
	testing.expect(t, layout_take_end(&empty, 2) == Rect{1, 10, 0, 0})
	testing.expect(t, layout_remaining(&empty) == Rect{1, 2, 0, 8})
	testing.expect(t, layout_take_rest(&empty) == Rect{1, 2, 0, 8})
	testing.expect(t, layout_remaining(&empty) == Rect{1, 10, 0, 0})
}

@(test)
layout_test_take_end_extreme :: proc(t: ^testing.T) {
	cursor := layout_init(Rect{max(int)-1, 0, 8, 1}, .Row, 1)
	testing.expect(t, layout_take_end(&cursor, 0) == Rect{max(int), 0, 0, 1})
	testing.expect(t, layout_take_end(&cursor, 1) == Rect{max(int), 0, 1, 1})
	testing.expect(t, layout_remaining(&cursor) == Rect{max(int)-1, 0, 0, 1})

	cursor = layout_init(Rect{0, max(int), 1, max(int)}, .Column)
	testing.expect(t, layout_take_end(&cursor, max(int)) == Rect{0, max(int), 1, 1})
	testing.expect(t, layout_remaining(&cursor) == Rect{0, max(int), 1, 0})

	cursor = layout_init(Rect{min(int), 0, max(int), 1}, .Row, max(int))
	testing.expect(t, layout_take_end(&cursor, 1) == Rect{-2, 0, 1, 1})
	testing.expect(t, layout_remaining(&cursor) == Rect{min(int), 0, 0, 1})

	cursor = layout_init(Rect{max(int)-1, 0, 10, 1}, .Row)
	testing.expect(t, layout_take_rest(&cursor) == Rect{max(int)-1, 0, 10, 1})
	testing.expect(t, layout_remaining(&cursor) == Rect{max(int), 0, 0, 1})
}

@(test)
test_layout_row_chunks :: proc(t: ^testing.T) {
	layout := layout_init(Rect{2, 3, 12, 4}, .Row, 2)
	testing.expect(t, layout_take(&layout, 3) == Rect{2, 3, 3, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_take(&layout, 0) == Rect{7, 3, 0, 4})
	testing.expect(t, layout_take(&layout, -1) == Rect{7, 3, 0, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_take(&layout, 100) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{14, 3, 0, 4})
	testing.expect(t, layout_take(&layout, 1) == Rect{14, 3, 0, 4})
}

@(test)
test_layout_column_and_empty :: proc(t: ^testing.T) {
	layout := layout_init(Rect{-3, 5, 6, 8}, .Column, 1)
	testing.expect(t, layout_take(&layout, 2) == Rect{-3, 5, 6, 2})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 8, 6, 5})
	testing.expect(t, layout_take(&layout, 3) == Rect{-3, 8, 6, 3})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 12, 6, 1})
	testing.expect(t, layout_take(&layout, 4) == Rect{-3, 12, 6, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 13, 6, 0})

	empty := layout_init(Rect{1, 2, -4, 8}, .Column, -1)
	testing.expect(t, layout_remaining(&empty) == Rect{1, 2, 0, 8})
	testing.expect(t, layout_take(&empty, 2) == Rect{1, 2, 0, 0})
	testing.expect(t, layout_remaining(&empty) == Rect{1, 2, 0, 8})
	no_gap := layout_init(Rect{0, 0, 3, 1}, .Row, -8)
	testing.expect(t, layout_take(&no_gap, 1) == Rect{0, 0, 1, 1})
	testing.expect(t, layout_remaining(&no_gap) == Rect{1, 0, 2, 1})
}

@(test)
test_layout_extreme_coordinates :: proc(t: ^testing.T) {
	layout := layout_init(Rect{max(int)-2, 0, 5, 1}, .Row, 0)
	testing.expect(t, layout_take(&layout, 2) == Rect{max(int)-2, 0, 2, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{max(int), 0, 3, 1})
	testing.expect(t, layout_take(&layout, 1) == Rect{max(int), 0, 1, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{max(int), 0, 0, 1})

	layout = layout_init(Rect{min(int), min(int), max(int), max(int)}, .Column, max(int))
	testing.expect(t, layout_take(&layout, 1) == Rect{min(int), min(int), max(int), 1})
	testing.expect(t, layout_remaining(&layout) == Rect{min(int), -1, max(int), 0})

	layout = layout_init(Rect{0, max(int)-1, 1, max(int)}, .Column, max(int))
	testing.expect(t, layout_take(&layout, 1) == Rect{0, max(int)-1, 1, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{0, max(int), 1, 0})
}
