package main

import "core:sys/linux"
import "core:sys/posix"

terminal_query_size :: proc() -> Terminal_Size {
	size: Terminal_Size
	_ = linux.ioctl(linux.Fd(posix.STDOUT_FILENO), linux.TIOCGWINSZ, uintptr(&size))
	return size
}
