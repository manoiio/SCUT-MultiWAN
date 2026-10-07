package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"syscall"
	"unsafe"
)

func socketControl(server bool, congestion string) func(string, string, syscall.RawConn) error {
	return func(_, _ string, raw syscall.RawConn) error {
		var result error
		e := raw.Control(func(fd uintptr) {
			// SO_*BUFFORCE applies to this proxy socket only; no global buffer edits.
			opt := 33
			if server {
				opt = 32
			}
			result = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, opt, 4<<20)
			if result == nil && congestion != "" {
				result = syscall.SetsockoptString(int(fd), syscall.IPPROTO_TCP, syscall.TCP_CONGESTION, congestion)
			}
		})
		if e != nil {
			return e
		}
		return result
	}
}

func mptcpState(c net.Conn) string {
	t, ok := c.(*net.TCPConn)
	if !ok {
		return "not TCPConn"
	}
	r, err := t.SyscallConn()
	if err != nil {
		return "raw unavailable"
	}
	b := make([]byte, 192)
	n := uint32(len(b))
	var errno syscall.Errno
	r.Control(func(fd uintptr) {
		_, _, errno = syscall.Syscall6(syscall.SYS_GETSOCKOPT, fd, 284, 1, uintptr(unsafe.Pointer(&b[0])), uintptr(unsafe.Pointer(&n)), 0)
	})
	if errno != 0 {
		return fmt.Sprintf("info error %d", errno)
	}
	return fmt.Sprintf("flags=%d additional=%d total=%d", binary.LittleEndian.Uint32(b[8:12]), b[0], b[80])
}
