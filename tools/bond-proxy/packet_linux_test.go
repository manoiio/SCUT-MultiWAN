package main

import (
	"os"
	"os/exec"
	"testing"
	"time"
)

// Run only in an explicitly created, isolated network namespace with CAP_NET_ADMIN.
func TestTunPollWakeups(t *testing.T) {
	if os.Getenv("SCUT_TUN_INTEGRATION") != "1" {
		t.Skip("isolated Linux namespace only")
	}
	for _, args := range [][]string{{"tuntap", "add", "dev", "scut-lan", "mode", "tun"}, {"addr", "add", "172.31.255.1/30", "dev", "scut-lan"}, {"link", "set", "scut-lan", "up"}} {
		if b, err := exec.Command("ip", args...).CombinedOutput(); err != nil {
			t.Fatalf("setup: %s %v", b, err)
		}
	}
	f, err := openTun("scut-lan")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cmd := exec.Command("ping", "-c", "3", "-i", "0.3", "-W", "1", "172.31.255.2")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	buf := make([]byte, 1500)
	for i := 0; i < 3; {
		f.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, err := f.Read(buf)
		if err != nil {
			t.Fatalf("lost delayed TUN wakeup #%d: %v", i, err)
		}
		// Bringing up the interface may enqueue IPv6 neighbour discovery first.
		if n < 28 || buf[0]>>4 != 4 || buf[9] != 1 {
			continue
		}
		i++
	}
}
