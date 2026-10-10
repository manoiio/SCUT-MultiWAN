//go:build !linux

package main

import "errors"

func runPacketServer(config) error { return errors.New("IP tunnel requires Linux TUN") }
func runPacketClient(config) error { return errors.New("IP tunnel requires Linux TUN") }
