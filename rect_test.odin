package odintui

import "core:testing"

@(test)
test_rect_intersection_and_contains :: proc(t: ^testing.T) {
	a := Rect{-2, 1, 5, 4}
	b := Rect{1, -1, 4, 4}
	testing.expect(t, rect_intersect(a, b) == Rect{1, 1, 2, 2})
	testing.expect(t, rect_intersect(b, a) == Rect{1, 1, 2, 2})
	testing.expect(t, rect_intersect(a, Rect{3, 1, 1, 1}) == Rect{3, 1, 0, 0})
	testing.expect(t, rect_intersect(a, Rect{0, 0, -1, 3}) == Rect{0, 1, 0, 0})
	testing.expect(t, rect_is_empty(Rect{0, 0, 1, 0}))
	testing.expect(t, !rect_is_empty(a))
	testing.expect(t, rect_contains(a, -2, 1))
	testing.expect(t, rect_contains(a, 2, 4))
	testing.expect(t, !rect_contains(a, 3, 4))
	testing.expect(t, !rect_contains(a, 2, 5))
	testing.expect(t, !rect_contains(Rect{0, 0, -1, 4}, 0, 0))

	extreme := Rect{max(int)-1, min(int), max(int), max(int)}
	testing.expect(t, rect_contains(extreme, max(int), -2))
	testing.expect(t, !rect_contains(extreme, max(int), -1))
	testing.expect(t, rect_intersect(extreme, Rect{max(int), -3, 2, 2}) ==
	                  Rect{max(int), -3, 2, 2})
	testing.expect(t, rect_intersect(Rect{min(int), 0, max(int), 1}, Rect{0, 0, 1, 1}) ==
	                  Rect{0, 0, 0, 0})
}

@(test)
test_rect_inset_and_align :: proc(t: ^testing.T) {
	r := Rect{2, 3, 10, 7}
	testing.expect(t, rect_inset(r, 2) == Rect{2+2, 3+2, 6, 3})
	testing.expect(t, rect_inset(r, -1) == r)
	testing.expect(t, rect_inset(r, Insets{1, 2, 3, 4}) == Rect{6, 4, 4, 3})
	testing.expect(t, rect_inset(r, Insets{-2, max(int), 0, 3}) == Rect{5, 3, 0, 7})
	testing.expect(t, rect_inset(r, max(int)) == Rect{12, 10, 0, 0})
	testing.expect(t, rect_inset(Rect{max(int), 0, 3, 1}, 1) == Rect{max(int), 1, 0, 0})

	testing.expect(t, rect_align(r, 3, 2, .Start, .End) == Rect{2, 8, 3, 2})
	testing.expect(t, rect_center(r, 3, 2) == Rect{5, 5, 3, 2})
	testing.expect(t, rect_align(r, max(int), -1, .End, .Start) == Rect{2, 3, 10, 0})
	testing.expect(t, rect_align(Rect{max(int), 0, 3, 1}, 1, 1, .End, .Start) ==
	                  Rect{max(int), 0, 0, 1})
	testing.expect(t, rect_center(Rect{min(int), min(int), max(int), max(int)}, 1, 1) ==
	                  Rect{min(int)+(max(int)-1)/2, min(int)+(max(int)-1)/2, 1, 1})
}
