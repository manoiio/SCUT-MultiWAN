package main

import (
	"encoding/binary"
	"errors"
	"io"
	"net"
)

const packetMTU = 1400

// Frames carry one IP packet; zero-length frames are liveness messages.
func readPacket(r io.Reader, buf []byte) ([]byte, error) {
	var header [2]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return nil, err
	}
	n := int(binary.BigEndian.Uint16(header[:]))
	if n > packetMTU || n > len(buf) {
		return nil, errors.New("oversize IP frame")
	}
	_, err := io.ReadFull(r, buf[:n])
	return buf[:n], err
}

func packetAddresses(p []byte) (net.IP, net.IP, error) {
	if len(p) < 20 {
		return nil, nil, errors.New("short IP packet")
	}
	switch p[0] >> 4 {
	case 4:
		ihl := int(p[0]&15) * 4
		if ihl < 20 || ihl > len(p) || int(binary.BigEndian.Uint16(p[2:4])) != len(p) {
			return nil, nil, errors.New("invalid IPv4 length")
		}
		return net.IP(p[12:16]), net.IP(p[16:20]), nil
	case 6:
		if len(p) < 40 || int(binary.BigEndian.Uint16(p[4:6]))+40 != len(p) {
			return nil, nil, errors.New("invalid IPv6 length")
		}
		return net.IP(p[8:24]), net.IP(p[24:40]), nil
	}
	return nil, nil, errors.New("unknown IP version")
}

func validPacket(p []byte, server bool) bool {
	src, dst, err := packetAddresses(p)
	if err != nil {
		return false
	}
	client4, client6 := net.ParseIP("172.31.255.2"), net.ParseIP("fd70:7363:7574::2")
	if !server {
		return dst.Equal(client4) || dst.Equal(client6)
	}
	if !src.Equal(client4) && !src.Equal(client6) {
		return false
	}
	// The peer addresses are allowed only for health checks to this tunnel.
	if dst.Equal(net.ParseIP("172.31.255.1")) || dst.Equal(net.ParseIP("fd70:7363:7574::1")) {
		return true
	}
	_, documentation6, _ := net.ParseCIDR("2001:db8::/32")
	return publicIP(dst) && !documentation6.Contains(dst)
}
