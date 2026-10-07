// Captures only ICMPv6 echo header metadata for one specified peer.
// No packet payload, credentials, or unrelated traffic is emitted.
package main

import (
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"runtime"
	"syscall"
	"time"
	"unsafe"
)

func main() {
	iface := flag.String("interface", "", "interface")
	peer := flag.String("peer", "", "IPv6 peer")
	seconds := flag.Int("seconds", 10, "capture duration, 1..30 seconds")
	flag.Parse()
	dev, err := net.InterfaceByName(*iface)
	p := net.ParseIP(*peer)
	if err != nil || p == nil || p.To4() != nil || *seconds < 1 || *seconds > 30 {
		fmt.Fprintln(os.Stderr, "invalid capture scope")
		os.Exit(2)
	}
	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW|syscall.SOCK_NONBLOCK, int(htons(3)))
	if err != nil {
		fmt.Fprintln(os.Stderr, "raw socket unavailable")
		os.Exit(1)
	}
	defer syscall.Close(fd)
	// ETH_P_ALL includes outgoing taps. BPF accepts only this peer's untagged
	// ICMPv6 echo frames and truncates at 62 bytes, before any payload.
	filters := echoFilter(p.To16())
	program := syscall.SockFprog{Len: uint16(len(filters)), Filter: &filters[0]}
	_, _, errno := syscall.Syscall6(syscall.SYS_SETSOCKOPT, uintptr(fd), syscall.SOL_SOCKET, 26, uintptr(unsafe.Pointer(&program)), unsafe.Sizeof(program), 0)
	runtime.KeepAlive(filters)
	if errno != 0 {
		fmt.Fprintln(os.Stderr, "scope filter unavailable")
		os.Exit(1)
	}
	if err = syscall.Bind(fd, &syscall.SockaddrLinklayer{Protocol: htons(3), Ifindex: dev.Index}); err != nil {
		fmt.Fprintln(os.Stderr, "interface bind failed")
		os.Exit(1)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.Encode(map[string]any{"event": "ready", "interface": dev.Name, "seconds": *seconds})
	deadline := time.Now().Add(time.Duration(*seconds) * time.Second)
	b := make([]byte, 4096)
	count := 0
	for time.Now().Before(deadline) && count < 100 {
		n, sa, e := syscall.Recvfrom(fd, b, 0)
		if e == syscall.EAGAIN || e == syscall.EWOULDBLOCK {
			time.Sleep(5 * time.Millisecond)
			continue
		}
		if e != nil {
			fmt.Fprintln(os.Stderr, "capture receive failed")
			os.Exit(1)
		}
		off := 14
		if n >= 18 && binary.BigEndian.Uint16(b[12:14]) == 0x8100 {
			off = 18
		}
		if n < off+48 || b[off]>>4 != 6 || b[off+6] != 58 {
			continue
		}
		src, dst := net.IP(b[off+8:off+24]), net.IP(b[off+24:off+40])
		if !src.Equal(p) && !dst.Equal(p) {
			continue
		}
		icmp := b[off+40 : off+48]
		if icmp[0] != 128 && icmp[0] != 129 {
			continue
		}
		ll, ok := sa.(*syscall.SockaddrLinklayer)
		if !ok {
			continue
		}
		dir := "in"
		if ll.Pkttype == syscall.PACKET_OUTGOING {
			dir = "out"
		}
		enc.Encode(map[string]any{"time": time.Now().UTC().Format(time.RFC3339Nano), "interface": dev.Name, "direction": dir, "packet_type": ll.Pkttype, "src": src.String(), "dst": dst.String(), "src_mac": net.HardwareAddr(b[6:12]).String(), "dst_mac": net.HardwareAddr(b[0:6]).String(), "ipv6_length": binary.BigEndian.Uint16(b[off+4 : off+6]), "hop_limit": b[off+7], "icmp_type": icmp[0], "id": binary.BigEndian.Uint16(icmp[4:6]), "sequence": binary.BigEndian.Uint16(icmp[6:8])})
		count++
	}
	enc.Encode(map[string]any{"event": "finished", "packets": count})
}
func htons(v uint16) uint16 { return v<<8 | v>>8 }

func echoFilter(p net.IP) []syscall.SockFilter {
	w := []uint32{binary.BigEndian.Uint32(p[0:4]), binary.BigEndian.Uint32(p[4:8]), binary.BigEndian.Uint32(p[8:12]), binary.BigEndian.Uint32(p[12:16])}
	return []syscall.SockFilter{
		{Code: 0x28, K: 12}, {Code: 0x15, K: 0x86dd, Jf: 22},
		{Code: 0x30, K: 20}, {Code: 0x15, K: 58, Jf: 20},
		{Code: 0x30, K: 54}, {Code: 0x15, K: 128, Jt: 1}, {Code: 0x15, K: 129, Jf: 17},
		{Code: 0x20, K: 22}, {Code: 0x15, K: w[0], Jf: 6},
		{Code: 0x20, K: 26}, {Code: 0x15, K: w[1], Jf: 4},
		{Code: 0x20, K: 30}, {Code: 0x15, K: w[2], Jf: 2},
		{Code: 0x20, K: 34}, {Code: 0x15, K: w[3], Jt: 8},
		{Code: 0x20, K: 38}, {Code: 0x15, K: w[0], Jf: 7},
		{Code: 0x20, K: 42}, {Code: 0x15, K: w[1], Jf: 5},
		{Code: 0x20, K: 46}, {Code: 0x15, K: w[2], Jf: 3},
		{Code: 0x20, K: 50}, {Code: 0x15, K: w[3], Jf: 1},
		{Code: 0x06, K: 62}, {Code: 0x06, K: 0},
	}
}
