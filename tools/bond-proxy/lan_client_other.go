//go:build !linux

package main

import (
	"errors"
	"syscall"
)

func watchProxySignals() {}
func lanSocketMark(string, string, syscall.RawConn) error {
	return errors.New("LAN routing requires Linux")
}
