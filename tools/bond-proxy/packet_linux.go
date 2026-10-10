package main

import (
	"bufio"
	"context"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Both ends attach to a persistent TUN created by the privileged setup service.
// The packet server otherwise runs as the existing dedicated scutbond user.
func openTun(name string) (*os.File, error) {
	if name != "scut-lan" {
		return nil, errors.New("unexpected TUN interface")
	}
	// Attach before os.NewFile registers epoll. An unbound TUN has no queue
	// for poll_wait(), so registering it earlier loses later packet wakeups.
	fd, err := syscall.Open("/dev/net/tun", syscall.O_RDWR|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	var ifr [40]byte
	copy(ifr[:16], name)
	binary.NativeEndian.PutUint16(ifr[16:18], 0x1001) // IFF_TUN | IFF_NO_PI
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), 0x400454ca, uintptr(unsafe.Pointer(&ifr[0])))
	if errno != 0 {
		syscall.Close(fd)
		return nil, errno
	}
	return os.NewFile(uintptr(fd), "/dev/net/tun"), nil
}

func bridgePackets(t net.Conn, r io.Reader, tun *os.File, server bool) error {
	var mu sync.Mutex
	done := make(chan error, 2)
	stop := make(chan struct{})
	writeFrame := func(p []byte) error {
		mu.Lock()
		defer mu.Unlock()
		t.SetWriteDeadline(time.Now().Add(15 * time.Second))
		var header [2]byte
		binary.BigEndian.PutUint16(header[:], uint16(len(p)))
		if _, err := t.Write(header[:]); err != nil {
			return err
		}
		if len(p) > 0 {
			_, err := t.Write(p)
			return err
		}
		return nil
	}
	go func() {
		buf := make([]byte, packetMTU+1)
		for {
			n, err := tun.Read(buf)
			if err != nil {
				done <- err
				return
			}
			if n > packetMTU {
				continue
			}
			if err = writeFrame(buf[:n]); err != nil {
				done <- err
				return
			}
		}
	}()
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				if err := writeFrame(nil); err != nil {
					t.Close()
					return
				}
			}
		}
	}()
	go func() {
		buf := make([]byte, packetMTU)
		for {
			t.SetReadDeadline(time.Now().Add(45 * time.Second))
			p, err := readPacket(r, buf)
			if err != nil {
				done <- err
				return
			}
			if len(p) == 0 || !validPacket(p, server) {
				continue
			}
			if _, err = tun.Write(p); err != nil {
				done <- err
				return
			}
		}
	}()
	err := <-done
	close(stop)
	t.Close()
	tun.Close()
	return err
}

func runPacketClient(c config) error {
	pem, err := os.ReadFile(c.CA)
	if err != nil {
		return err
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(pem) {
		return errors.New("invalid server certificate")
	}
	if c.TunInterface != "scut-lan" || c.ReadyFile != "/var/run/scut-lan/tunnel.ready" {
		return errors.New("invalid packet client configuration")
	}
	for {
		os.Remove(c.ReadyFile)
		t, err := dialTunnel(c, roots, "@ip:1")
		if err == nil {
			var tun *os.File
			tun, err = openTun(c.TunInterface)
			if err == nil {
				err = os.WriteFile(c.ReadyFile, []byte("authenticated\n"), 0600)
				if err == nil {
					err = bridgePackets(t, t, tun, false)
				} else {
					tun.Close()
					t.Close()
				}
			} else {
				t.Close()
			}
		}
		os.Remove(c.ReadyFile)
		log.Print("IP tunnel disconnected; retry in 3s")
		time.Sleep(3 * time.Second)
	}
}

func runPacketServer(c config) error {
	if c.TunInterface != "scut-lan" {
		return errors.New("invalid packet server TUN")
	}
	cert, err := tls.LoadX509KeyPair(c.Certificate, c.Key)
	if err != nil {
		return err
	}
	lc := net.ListenConfig{Control: socketControl(true, c.CongestionControl)}
	lc.SetMultipathTCP(true)
	l, err := lc.Listen(context.Background(), c.TransportNetwork, c.Listen)
	if err != nil {
		return err
	}
	defer l.Close()
	sem := make(chan struct{}, 1)
	log.Print("IP TLS/MPTCP server ready")
	for {
		raw, err := l.Accept()
		if err != nil {
			return err
		}
		select {
		case sem <- struct{}{}:
		default:
			raw.Close()
			continue
		}
		go func() {
			defer func() { <-sem }()
			defer raw.Close()
			tcp, ok := raw.(*net.TCPConn)
			if !ok {
				return
			}
			active, err := tcp.MultipathTCP()
			if err != nil || !active {
				return
			}
			raw.SetDeadline(time.Now().Add(12 * time.Second))
			var magic [8]byte
			if _, err := io.ReadFull(raw, magic[:]); err != nil || string(magic[:]) != "SCUTB1\r\n" {
				return
			}
			if _, err := io.WriteString(raw, "SCUTB1\r\n"); err != nil {
				return
			}
			t := tls.Server(raw, &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})
			if t.Handshake() != nil {
				return
			}
			r := bufio.NewReaderSize(t, 4096)
			var q request
			if readJSONLine(r, &q) != nil || q.Target != "@ip:1" || subtle.ConstantTimeCompare([]byte(q.Token), []byte(c.Token)) != 1 {
				return
			}
			tun, err := openTun(c.TunInterface)
			if err != nil {
				writeJSON(t, response{Error: "IP tunnel unavailable"})
				return
			}
			if writeJSON(t, response{OK: true}) != nil {
				tun.Close()
				return
			}
			t.SetDeadline(time.Time{})
			log.Print("authenticated IP tunnel opened")
			bridgePackets(t, r, tun, true)
		}()
	}
}
