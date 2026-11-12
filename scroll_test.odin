package odintui

import "core:testing"

@(test)
scroll_test_clamp :: proc(t: ^testing.T) {
	testing.expect(t, scroll_clamp(-5, 100, 10) == 0)
	testing.expect(t, scroll_clamp(99, 100, 10) == 90)
	testing.expect(t, scroll_clamp(10, 4, 8) == 0)
	testing.expect(t, scroll_clamp(4, -1, -2) == 0)
	testing.expect(t, scroll_clamp(max(int), max(int), 0) == max(int))
	testing.expect(t, scroll_clamp(max(int), max(int), max(int)-1) == 1)
}

@(test)
scroll_test_into_view :: proc(t: ^testing.T) {
	testing.expect(t, scroll_into_view(10, 12, 3, 10) == 10)
	testing.expect(t, scroll_into_view(10, 7, 2, 10) == 7)
	testing.expect(t, scroll_into_view(10, 18, 5, 10) == 13)
	testing.expect(t, scroll_into_view(10, 12, 11, 10) == 12)
	testing.expect(t, scroll_into_view(10, 12, 2, 0) == 12)
	testing.expect(t, scroll_into_view(10, 0, 0, 3) == 10)
	testing.expect(t, scroll_into_view(-1, -9, 2, 3) == 0)
	testing.expect(t, scroll_into_view(max(int)-5, max(int)-1, 4, 5) == max(int)-2)
	testing.expect(t, scroll_into_view(max(int), max(int), max(int), max(int)-1) == max(int))
}
