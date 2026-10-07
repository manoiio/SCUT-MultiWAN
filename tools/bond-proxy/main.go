// scut-bond provides an opt-in LAN proxy over an authenticated TLS/MPTCP link.
// CDN TLS remains end-to-end. No request URLs or authentication material are logged.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

type config struct {
	Mode              string            `json:"mode"`
	Listen            string            `json:"listen"`
	Server            string            `json:"server"`
	FallbackServer    string            `json:"fallback_server"`
	FallbackLocalFile string            `json:"fallback_local_address_file"`
	TransportNetwork  string            `json:"transport_network"`
	CongestionControl string            `json:"congestion_control"`
	PreferredIPv4     map[string]string `json:"preferred_upstream_ipv4"`
	Token             string            `json:"token"`
	Certificate       string            `json:"certificate"`
	Key               string            `json:"key"`
	CA                string            `json:"ca"`
	LocalAddressFile  string            `json:"local_address_file"`
	AllowedClientCIDR string            `json:"allowed_client_cidr"`
	MaxConnections    int               `json:"max_connections"`
	Benchmark         bool              `json:"benchmark"`
	BenchmarkBudget   int64             `json:"benchmark_budget"`
}
type request struct {
	Token  string `json:"token"`
	Target string `json:"target"`
}
type response struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

var benchmarkLeft atomic.Int64

func loadConfig(path string) (config, error) {
	var c config
	b, e := os.ReadFile(path)
	if e != nil {
		return c, e
	}
	if e = json.Unmarshal(b, &c); e != nil {
		return c, e
	}
	if len(c.Token) < 32 {
		return c, errors.New("token must contain at least 32 characters")
	}
	if c.MaxConnections < 1 || c.MaxConnections > 32 {
		c.MaxConnections = 8
	}
	if c.TransportNetwork == "" {
		c.TransportNetwork = "tcp4"
	}
	if c.TransportNetwork != "tcp4" && c.TransportNetwork != "tcp6" && c.TransportNetwork != "tcp" {
		return c, errors.New("transport_network must be tcp, tcp4 or tcp6")
	}
	if c.CongestionControl != "" && c.CongestionControl != "cubic" && c.CongestionControl != "bbr" {
		return c, errors.New("congestion_control must be empty, cubic or bbr")
	}
	if len(c.PreferredIPv4) > 8 || (len(c.PreferredIPv4) > 0 && c.Mode != "server") {
		return c, errors.New("upstream preferences require a server and at most eight hosts")
	}
	if len(c.PreferredIPv4) > 0 {
		normalized := make(map[string]string, len(c.PreferredIPv4))
		for host, address := range c.PreferredIPv4 {
			host = strings.TrimSuffix(strings.ToLower(host), ".")
			ip := net.ParseIP(address)
			if host == "" || strings.ContainsAny(host, ":/ \t\r\n") || ip == nil || ip.To4() == nil || !publicIP(ip) {
				return c, errors.New("invalid upstream IPv4 preference")
			}
			if _, exists := normalized[host]; exists {
				return c, errors.New("duplicate upstream preference host")
			}
			normalized[host] = ip.String()
		}
		c.PreferredIPv4 = normalized
	}
	if c.FallbackServer != "" || c.FallbackLocalFile != "" {
		h, p, err := net.SplitHostPort(c.FallbackServer)
		ip := net.ParseIP(h)
		port, perr := strconv.Atoi(p)
		if c.Mode != "client" || c.TransportNetwork != "tcp" || c.FallbackLocalFile == "" || err != nil || perr != nil || port < 1 || port > 65535 || ip == nil || ip.To4() == nil || !publicIP(ip) {
			return c, errors.New("fallback requires a dual-stack client, public IPv4 server and local address file")
		}
	}
	return c, nil
}
func readJSONLine(r *bufio.Reader, v any) error {
	b, e := r.ReadSlice('\n')
	if e != nil {
		return e
	}
	if len(b) > 2048 {
		return errors.New("header too large")
	}
	return json.Unmarshal(b, v)
}
func writeJSON(w io.Writer, v any) error { return json.NewEncoder(w).Encode(v) }
func main() {
	p := flag.String("config", "", "private JSON configuration path")
	flag.Parse()
	c, e := loadConfig(*p)
	if e != nil {
		log.Fatal(e)
	}
	benchmarkLeft.Store(c.BenchmarkBudget)
	if c.Mode == "server" {
		e = runServer(c)
	} else if c.Mode == "client" {
		e = runClient(c)
	} else {
		e = errors.New("invalid mode")
	}
	if e != nil {
		log.Fatal(e)
	}
}
func runServer(c config) error {
	cert, e := tls.LoadX509KeyPair(c.Certificate, c.Key)
	if e != nil {
		return e
	}
	lc := net.ListenConfig{Control: socketControl(true, c.CongestionControl)}
	lc.SetMultipathTCP(true)
	l, e := lc.Listen(context.Background(), c.TransportNetwork, c.Listen)
	if e != nil {
		return e
	}
	defer l.Close()
	sem := make(chan struct{}, c.MaxConnections)
	log.Print("TLS/MPTCP server ready")
	for {
		raw, e := l.Accept()
		if e != nil {
			return e
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
			raw.SetDeadline(time.Now().Add(12 * time.Second))
			magic := make([]byte, 8)
			if _, e := io.ReadFull(raw, magic); e != nil || string(magic) != "SCUTB1\r\n" {
				return
			}
			if _, e := io.WriteString(raw, "SCUTB1\r\n"); e != nil {
				return
			}
			t := tls.Server(raw, &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})
			t.SetDeadline(time.Now().Add(12 * time.Second))
			if t.Handshake() != nil {
				return
			}
			r := bufio.NewReaderSize(t, 4096)
			var q request
			if readJSONLine(r, &q) != nil || subtle.ConstantTimeCompare([]byte(q.Token), []byte(c.Token)) != 1 {
				return
			}
			if strings.HasPrefix(q.Target, "@benchmark:") {
				serveBenchmark(c, t, q.Target)
				return
			}
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			up, e := dialPublicPreferred(ctx, q.Target, c.PreferredIPv4)
			if e != nil {
				writeJSON(t, response{Error: "target unavailable"})
				return
			}
			defer up.Close()
			log.Print("public target connected: ", up.RemoteAddr())
			if writeJSON(t, response{OK: true}) != nil {
				return
			}
			t.SetDeadline(time.Time{})
			copyTunnel(t, r, up)
		}()
	}
}
func serveBenchmark(c config, t net.Conn, target string) {
	n, e := strconv.ParseInt(strings.TrimPrefix(target, "@benchmark:"), 10, 64)
	if !c.Benchmark || e != nil || n < 1 || n > 512<<20 {
		writeJSON(t, response{Error: "benchmark disabled"})
		return
	}
	for {
		left := benchmarkLeft.Load()
		if n > left {
			writeJSON(t, response{Error: "benchmark budget exhausted"})
			return
		}
		if benchmarkLeft.CompareAndSwap(left, left-n) {
			break
		}
	}
	if writeJSON(t, response{OK: true}) != nil {
		return
	}
	t.SetDeadline(time.Now().Add(60 * time.Second))
	buf := make([]byte, 64<<10)
	for i := range buf {
		buf[i] = byte(i)
	}
	for n > 0 {
		q := int64(len(buf))
		if n < q {
			q = n
		}
		if _, e = t.Write(buf[:q]); e != nil {
			return
		}
		n -= q
	}
}
func publicIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	// Reject shared, documentation, benchmarking and reserved IPv4 destinations too.
	for _, cidr := range []string{"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "240.0.0.0/4"} {
		_, n, _ := net.ParseCIDR(cidr)
		if n.Contains(ip) {
			return false
		}
	}
	return true
}
func dialPublic(ctx context.Context, target string) (net.Conn, error) {
	return dialPublicPreferred(ctx, target, nil)
}

// A preference only orders addresses returned by the current DNS lookup. It
// never adds a stale address or bypasses the validation of the entire answer.
func orderPublicIPs(ips []net.IP, host string, preferences map[string]string) []net.IP {
	preferred := net.ParseIP(preferences[strings.TrimSuffix(strings.ToLower(host), ".")])
	if preferred == nil {
		return ips
	}
	for i, ip := range ips {
		if i > 0 && ip.Equal(preferred) {
			ordered := append([]net.IP(nil), ips...)
			copy(ordered[1:i+1], ips[:i])
			ordered[0] = ip
			return ordered
		}
	}
	return ips
}

func dialPublicPreferred(ctx context.Context, target string, preferences map[string]string) (net.Conn, error) {
	h, p, e := net.SplitHostPort(target)
	if e != nil || h == "" || (p != "80" && p != "443") {
		return nil, errors.New("only public web ports are permitted")
	}
	ips, e := net.DefaultResolver.LookupIP(ctx, "ip4", h)
	if e != nil {
		return nil, e
	}
	if len(ips) == 0 {
		return nil, errors.New("no IPv4 target")
	}
	for _, ip := range ips {
		if !publicIP(ip) {
			return nil, errors.New("nonpublic target rejected")
		}
	}
	ips = orderPublicIPs(ips, h, preferences)
	var last error
	for _, ip := range ips {
		d := net.Dialer{Timeout: 5 * time.Second}
		v, e := d.DialContext(ctx, "tcp4", net.JoinHostPort(ip.String(), p))
		if e == nil {
			return v, nil
		}
		last = e
	}
	return nil, last
}
func runClient(c config) error {
	pem, e := os.ReadFile(c.CA)
	if e != nil {
		return e
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(pem) {
		return errors.New("invalid server certificate")
	}
	_, allowed, e := net.ParseCIDR(c.AllowedClientCIDR)
	if e != nil {
		return e
	}
	l, e := net.Listen("tcp4", c.Listen)
	if e != nil {
		return e
	}
	defer l.Close()
	sem := make(chan struct{}, c.MaxConnections)
	log.Print("LAN HTTP/SOCKS5 proxy ready")
	for {
		v, e := l.Accept()
		if e != nil {
			return e
		}
		ip, _, _ := net.SplitHostPort(v.RemoteAddr().String())
		if !allowed.Contains(net.ParseIP(ip)) {
			v.Close()
			continue
		}
		select {
		case sem <- struct{}{}:
		default:
			v.Close()
			continue
		}
		go func() {
			defer func() { <-sem }()
			defer v.Close()
			v.SetDeadline(time.Now().Add(15 * time.Second))
			r := bufio.NewReaderSize(v, 8192)
			first, e := r.Peek(1)
			if e != nil {
				return
			}
			if first[0] == 5 {
				serveSOCKS(c, roots, v, r)
			} else {
				serveHTTP(c, roots, v, r)
			}
		}()
	}
}
func dialTunnel(c config, roots *x509.CertPool, target string) (*tls.Conn, error) {
	ip, e := readLocalAddress(c.LocalAddressFile)
	if e != nil {
		return nil, e
	}
	network, server := transportTarget(c, ip)
	t, e := openTransport(c, roots, ip, network, server)
	// Retry only transport setup, before sending a target or any CDN request.
	// The same CA, TLS identity, MPTCP requirement and token remain mandatory.
	if e != nil && ip.To4() == nil && c.FallbackServer != "" {
		v4, localErr := readLocalAddress(c.FallbackLocalFile)
		if localErr == nil && v4.To4() != nil {
			log.Print("IPv6 transport unavailable; trying configured IPv4 MPTCP path")
			t, e = openTransport(c, roots, v4, "tcp4", c.FallbackServer)
		}
	}
	if e != nil {
		return nil, e
	}
	if e = writeJSON(t, request{Token: c.Token, Target: target}); e != nil {
		t.Close()
		return nil, e
	}
	// The server sends only its response line before the client starts forwarding.
	var line []byte
	one := make([]byte, 1)
	for len(line) < 2048 {
		if _, e = io.ReadFull(t, one); e != nil {
			break
		}
		line = append(line, one[0])
		if one[0] == '\n' {
			break
		}
	}
	var result response
	if e != nil || json.Unmarshal(line, &result) != nil || !result.OK {
		t.Close()
		return nil, errors.New("tunnel rejected")
	}
	t.SetDeadline(time.Time{})
	log.Print("authenticated MPTCP tunnel opened")
	return t, nil
}

func readLocalAddress(path string) (net.IP, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	ip := net.ParseIP(strings.TrimSpace(string(b)))
	if ip == nil {
		return nil, errors.New("no healthy local address")
	}
	return ip, nil
}

func transportTarget(c config, ip net.IP) (string, string) {
	if ip.To4() != nil && c.FallbackServer != "" {
		return "tcp4", c.FallbackServer
	}
	return c.TransportNetwork, c.Server
}

func openTransport(c config, roots *x509.CertPool, ip net.IP, network, server string) (*tls.Conn, error) {
	dialTimeout, handshakeTimeout := 8*time.Second, 12*time.Second
	if c.FallbackServer != "" {
		dialTimeout, handshakeTimeout = 3*time.Second, 5*time.Second
	}
	d := net.Dialer{Timeout: dialTimeout, LocalAddr: &net.TCPAddr{IP: ip}, Control: socketControl(false, c.CongestionControl)}
	d.SetMultipathTCP(true)
	raw, e := d.DialContext(context.Background(), network, server)
	if e != nil {
		return nil, e
	}
	tcp, ok := raw.(*net.TCPConn)
	if !ok {
		raw.Close()
		return nil, errors.New("unexpected transport")
	}
	active, e := tcp.MultipathTCP()
	if e != nil || !active {
		raw.Close()
		return nil, errors.New("MPTCP unavailable; fallback rejected")
	}
	log.Print("MPTCP before TLS: ", mptcpState(raw))
	raw.SetDeadline(time.Now().Add(handshakeTimeout))
	if _, e = io.WriteString(raw, "SCUTB1\r\n"); e != nil {
		raw.Close()
		return nil, e
	}
	magic := make([]byte, 8)
	if _, e = io.ReadFull(raw, magic); e != nil || string(magic) != "SCUTB1\r\n" {
		raw.Close()
		return nil, errors.New("transport preamble rejected")
	}
	t := tls.Client(raw, &tls.Config{RootCAs: roots, ServerName: "scut-bond-vps", MinVersion: tls.VersionTLS13})
	t.SetDeadline(time.Now().Add(handshakeTimeout))
	if e = t.Handshake(); e != nil {
		t.Close()
		return nil, e
	}
	log.Print("MPTCP after TLS: ", mptcpState(raw))
	active, e = tcp.MultipathTCP()
	if e != nil || !active {
		t.Close()
		return nil, errors.New("MPTCP fell back during handshake")
	}
	return t, nil
}
func serveSOCKS(c config, roots *x509.CertPool, v net.Conn, r *bufio.Reader) {
	h := make([]byte, 2)
	if _, e := io.ReadFull(r, h); e != nil {
		return
	}
	methods := make([]byte, int(h[1]))
	if _, e := io.ReadFull(r, methods); e != nil {
		return
	}
	noauth := false
	for _, m := range methods {
		noauth = noauth || m == 0
	}
	if !noauth {
		v.Write([]byte{5, 255})
		return
	}
	v.Write([]byte{5, 0})
	h = make([]byte, 4)
	if _, e := io.ReadFull(r, h); e != nil || h[0] != 5 || h[1] != 1 || h[2] != 0 {
		return
	}
	var host string
	switch h[3] {
	case 1:
		b := make([]byte, 4)
		if _, e := io.ReadFull(r, b); e != nil {
			return
		}
		host = net.IP(b).String()
	case 3:
		n, e := r.ReadByte()
		if e != nil || n == 0 {
			return
		}
		b := make([]byte, int(n))
		if _, e = io.ReadFull(r, b); e != nil {
			return
		}
		host = string(b)
	default:
		v.Write([]byte{5, 8, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	p := make([]byte, 2)
	if _, e := io.ReadFull(r, p); e != nil {
		return
	}
	target := net.JoinHostPort(host, strconv.Itoa(int(binary.BigEndian.Uint16(p))))
	u, e := dialTunnel(c, roots, target)
	if e != nil {
		v.Write([]byte{5, 1, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer u.Close()
	if _, e = v.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); e != nil {
		return
	}
	v.SetDeadline(time.Time{})
	copyTunnel(v, r, u)
}
func serveHTTP(c config, roots *x509.CertPool, v net.Conn, r *bufio.Reader) {
	q, tail, e := readHTTPRequest(r)
	if e != nil {
		return
	}
	defer q.Body.Close()
	if len(q.Header) > 100 {
		return
	}
	if q.Method == "GET" && strings.HasPrefix(q.URL.Path, "/__scut_benchmark/") {
		n, e := strconv.ParseInt(strings.TrimPrefix(q.URL.Path, "/__scut_benchmark/"), 10, 64)
		if e != nil || n < 1 || n > 512<<20 {
			return
		}
		u, e := dialTunnel(c, roots, fmt.Sprintf("@benchmark:%d", n))
		if e != nil {
			httpError(v)
			return
		}
		defer u.Close()
		v.SetDeadline(time.Time{})
		fmt.Fprintf(v, "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n", n)
		io.CopyN(v, u, n)
		return
	}
	target := q.Host
	if q.Method != "CONNECT" {
		if q.URL.Scheme != "http" || q.URL.Host == "" {
			httpError(v)
			return
		}
		target = q.URL.Host
		if _, _, e = net.SplitHostPort(target); e != nil {
			target = net.JoinHostPort(target, "80")
		}
	}
	u, e := dialTunnel(c, roots, target)
	if e != nil {
		httpError(v)
		return
	}
	defer u.Close()
	v.SetDeadline(time.Time{})
	if q.Method == "CONNECT" {
		if _, e = io.WriteString(v, "HTTP/1.1 200 Connection Established\r\n\r\n"); e != nil {
			return
		}
		copyTunnel(v, tail, u)
		return
	}
	q.RequestURI = ""
	q.Close = true
	q.Header.Del("Proxy-Authorization")
	q.Header.Del("Proxy-Connection")
	if e = q.Write(u); e != nil {
		return
	}
	io.Copy(v, u)
}

func readHTTPRequest(r *bufio.Reader) (*http.Request, *bufio.Reader, error) {
	var header []byte
	for len(header) < 32<<10 {
		b, err := r.ReadByte()
		if err != nil {
			return nil, nil, err
		}
		header = append(header, b)
		if bytes.HasSuffix(header, []byte("\r\n\r\n")) {
			joined := bufio.NewReader(io.MultiReader(bytes.NewReader(header), r))
			q, err := http.ReadRequest(joined)
			return q, joined, err
		}
	}
	return nil, nil, errors.New("HTTP header exceeds 32KiB")
}
func httpError(v io.Writer) {
	io.WriteString(v, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
}
func copyTunnel(a net.Conn, ar io.Reader, b net.Conn) {
	done := make(chan struct{}, 1)
	go func() {
		io.Copy(b, ar)
		if w, ok := b.(interface{ CloseWrite() error }); ok {
			w.CloseWrite()
		}
		done <- struct{}{}
	}()
	io.Copy(a, b)
	// Stop the opposite copier promptly on response EOF, avoiding stale goroutines.
	a.SetDeadline(time.Now())
	b.SetDeadline(time.Now())
	<-done
}
