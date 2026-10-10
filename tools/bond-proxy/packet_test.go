package main

import (
	"bytes"
	"encoding/binary"
	"net"
	"testing"
)

func ipv4Packet(src, dst string) []byte {
	p := make([]byte, 28)
	p[0] = 0x45
	p[9] = 17
	binary.BigEndian.PutUint16(p[2:4], uint16(len(p)))
	copy(p[12:16], net.ParseIP(src).To4())
	copy(p[16:20], net.ParseIP(dst).To4())
	return p
}
func TestPacketFramingAndPolicy(t *testing.T) {
	p := ipv4Packet("172.31.255.2", "1.1.1.1")
	wire := append([]byte{0, byte(len(p))}, p...)
	r := bytes.NewReader(wire)
	got, err := readPacket(r, make([]byte, packetMTU))
	if err != nil || !bytes.Equal(got, p) || !validPacket(p, true) {
		t.Fatal("valid UDP frame rejected")
	}
	for _, dst := range []string{"10.10.10.13", "192.168.1.98", "169.254.169.254", "127.0.0.1", "224.0.0.1", "198.18.0.1"} {
		if validPacket(ipv4Packet("172.31.255.2", dst), true) {
			t.Fatal("private destination accepted", dst)
		}
	}
	if validPacket(ipv4Packet("192.168.1.2", "1.1.1.1"), true) {
		t.Fatal("spoofed source accepted")
	}
	if !validPacket(ipv4Packet("1.1.1.1", "172.31.255.2"), false) {
		t.Fatal("reply rejected")
	}
	if validPacket(ipv4Packet("1.1.1.1", "192.168.1.2"), false) {
		t.Fatal("wrong reply destination accepted")
	}
	p[2] = 1
	if validPacket(p, true) {
		t.Fatal("invalid IP length accepted")
	}
	for _, wire := range [][]byte{{0, 0}, {0, 20, 1}, {255, 255}} {
		got, err := readPacket(bytes.NewReader(wire), make([]byte, packetMTU))
		if len(wire) == 2 && wire[1] == 0 {
			if err != nil || len(got) != 0 {
				t.Fatal("heartbeat rejected")
			}
		} else if err == nil {
			t.Fatal("truncated or oversize frame accepted")
		}
	}
}
func TestIPv6PacketPolicy(t *testing.T) {
	p := make([]byte, 48)
	p[0] = 0x60
	p[6] = 17
	binary.BigEndian.PutUint16(p[4:6], 8)
	copy(p[8:24], net.ParseIP("fd70:7363:7574::2"))
	copy(p[24:40], net.ParseIP("2606:4700:4700::1111"))
	if !validPacket(p, true) {
		t.Fatal("IPv6 UDP rejected")
	}
	copy(p[24:40], net.ParseIP("fd00::13"))
	if validPacket(p, true) {
		t.Fatal("ULA destination accepted")
	}
	copy(p[24:40], net.ParseIP("2001:db8::13"))
	if validPacket(p, true) {
		t.Fatal("documentation destination accepted")
	}
	if _, _, err := packetAddresses(p[:25]); err == nil {
		t.Fatal("short IPv6 accepted")
	}
}
