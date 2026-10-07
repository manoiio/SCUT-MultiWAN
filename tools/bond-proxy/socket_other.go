//go:build !linux

package main

import (
	"net"
	"syscall"
)

func socketControl(bool, string) func(string, string, syscall.RawConn) error { return nil }
func mptcpState(net.Conn) string                                             { return "unavailable" }
