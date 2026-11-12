# odintui

A small, backend-agnostic TUI drawing library written in Odin, using only
Odin's standard `base` and `core` libraries. There are no third-party
dependencies.

## Run

Install the Odin compiler and run these commands from the repository root:

```sh
odin check . -no-entry-point
odin test .
odin run examples/demo
```

The demo draws a border, labels and a progress bar using a column layout. It
renders an initial frame, an update, and an unchanged frame, reporting the
backend's draw-run, cell and flush counts. Its application-owned backend stores
a plain-text snapshot and prints it without terminal control sequences; it
works with redirected output. It substitutes `?` for every glyph outside
printable ASCII and intentionally ignores styles. The `Input: ??` in its
output demonstrates replacement of an escape character and a wide rune.

## Using the library

Import the root package from your application (the demo uses `import tui
"../.."`). `grid_init(width, height)` returns a `Grid` and a `Grid_Error`;
check for `.None` and call `grid_destroy(&grid)` when finished. An optional
allocator can be passed to `grid_init`; it must outlive the grid. A grid owns
its buffers: do not copy it or mutate its fields directly. Use `grid_bounds`,
`get_cell`, `set_cell`, `fill`, `draw_text` and `grid_resize` instead.
Resize preserves the overlap, blanks newly exposed cells and leaves the grid
unchanged on error.

`layout_init` and `layout_take` divide a rectangle into rows or columns, with
an optional gap. `draw_label`, `draw_border` and `draw_progress_bar` draw
into the grid; they do not manage application state. Text is clipped, not
automatically wrapped. Each decoded rune occupies one **logical** cell: no
grapheme segmentation or terminal Unicode-width calculation is performed.

`Style` contains foreground/background colors and attributes. A zero `Color`
means the backend's default color; `rgb(0, 0, 0)` is explicit black. A space
with a style is still a styled cell and is not equivalent to `BLANK_CELL`.

## Backends and application lifecycle

The host owns the input, event loop, backend and any terminal setup and
cleanup. The library does not open a terminal, read input or handle resize
events. On resize, update the backend and call `grid_resize`; the backend must
also clear any old viewport left outside a smaller grid.

Provide a `Backend` with `draw_run` and `flush` callbacks, as in the demo.
`draw_run` receives a borrowed slice of adjacent cells for one row; callbacks
must not retain or modify it, mutate the grid, or assume they will not be
retried. Give rendering exclusive access to the grid and backend. A real
terminal backend must sanitize control and invalid runes and map glyphs to
single-column printable output; the grid does not do this for it.

`render` sends changed runs and commits the presented state only after a
successful flush. Check its boolean result: a failed callback may already have
applied part of a frame, so repair the backend and retry; the next render
redraws the whole nonempty grid. Unchanged or empty grids do not call the
backend. Call `invalidate(&grid)` before rendering to a different backend or
after out-of-band screen changes or loss of backend contents.
