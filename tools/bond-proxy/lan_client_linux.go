package main

import (
	"os"
	"os/signal"
	"syscall"
)

func watchProxySignals() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGHUP)
	go func() {
		for range c {
			proxyConnections.closeAll()
		}
	}()
}
func lanSocketMark(_, _ string, raw syscall.RawConn) error {
	var err error
	if e := raw.Control(func(fd uintptr) { err = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, 36, 0x5343) }); e != nil {
		return e
	}
	return err
}
