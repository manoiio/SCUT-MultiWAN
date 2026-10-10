package main

import (
	"errors"
	"net"
	"os"
	"strings"
	"sync"
)

type connectionPool struct {
	mu         sync.Mutex
	active     map[net.Conn]bool
	generation uint64
}

var proxyConnections = connectionPool{active: make(map[net.Conn]bool)}

type pooledConnection struct {
	net.Conn
	pool *connectionPool
}

func (c *pooledConnection) Close() error {
	c.pool.mu.Lock()
	delete(c.pool.active, c.Conn)
	c.pool.mu.Unlock()
	return c.Conn.Close()
}
func (c *pooledConnection) CloseWrite() error {
	if half, ok := c.Conn.(interface{ CloseWrite() error }); ok {
		return half.CloseWrite()
	}
	return nil
}
func (p *connectionPool) track(c net.Conn) net.Conn {
	p.mu.Lock()
	p.active[c] = true
	p.mu.Unlock()
	return &pooledConnection{Conn: c, pool: p}
}
func (p *connectionPool) closeAll() {
	p.mu.Lock()
	old := p.active
	p.active = make(map[net.Conn]bool)
	p.generation++
	p.mu.Unlock()
	for c := range old {
		c.Close()
	}
}
func (p *connectionPool) version() uint64 { p.mu.Lock(); defer p.mu.Unlock(); return p.generation }
func (p *connectionPool) trackExpected(c net.Conn, generation uint64) (net.Conn, error) {
	p.mu.Lock()
	if generation != p.generation {
		p.mu.Unlock()
		c.Close()
		return nil, errors.New("proxy mode changed during setup")
	}
	p.active[c] = true
	p.mu.Unlock()
	return &pooledConnection{Conn: c, pool: p}, nil
}
func readLANMode(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	m := strings.TrimSpace(string(b))
	switch m {
	case "tunnel", "multi", "wired":
		return m, nil
	}
	return "", errors.New("invalid LAN mode")
}
func trackModeConnection(c config, mode string, conn net.Conn, generation uint64) (net.Conn, error) {
	if c.LANEgressModeFile == "" {
		return conn, nil
	}
	if current, err := readLANMode(c.LANEgressModeFile); err != nil || current != mode {
		conn.Close()
		return nil, errors.New("LAN mode changed during connection setup")
	}
	return proxyConnections.trackExpected(conn, generation)
}
