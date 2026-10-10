package main

import (
	"net"
	"os"
	"testing"
	"time"
)

func TestModeSetupAndConnectionClosure(t *testing.T) {
	p := t.TempDir() + "/mode"
	if _, err := readLANMode(p); err == nil {
		t.Fatal("missing mode accepted")
	}
	for _, mode := range []string{"multi", "wired", "tunnel", "wired;bad"} {
		os.WriteFile(p, []byte(mode+"\n"), 0600)
		got, err := readLANMode(p)
		if mode == "wired;bad" {
			if err == nil {
				t.Fatal("invalid mode accepted")
			}
		} else if err != nil || got != mode {
			t.Fatal("valid mode rejected")
		}
	}
	pool := connectionPool{active: make(map[net.Conn]bool)}
	a, b := net.Pipe()
	defer b.Close()
	tracked := pool.track(a)
	version := pool.version()
	pool.closeAll()
	tracked.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := tracked.Read(make([]byte, 1)); err == nil {
		t.Fatal("old connection survived mode change")
	}
	late, peer := net.Pipe()
	defer peer.Close()
	if _, err := pool.trackExpected(late, version); err == nil {
		t.Fatal("old setup generation survived mode change")
	}
	os.WriteFile(p, []byte("wired\n"), 0600)
	c, d := net.Pipe()
	defer d.Close()
	if _, err := trackModeConnection(config{LANEgressModeFile: p}, "tunnel", c, proxyConnections.version()); err == nil {
		t.Fatal("changed mode accepted after dialing")
	}
}
