package host
import "core:sys/darwin"
query_size :: proc() -> Terminal_Size {
	s: Terminal_Size
	_ = darwin.syscall_ioctl(1, darwin.TIOCGWINSZ, &s)
	return s
}
