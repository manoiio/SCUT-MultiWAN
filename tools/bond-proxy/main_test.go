package main

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"strings"
	"testing"
)

func TestTransportConfiguration(t *testing.T) {
	for _, network := range []string{"", "tcp4", "tcp6", "udp6", "tcp"} {
		b, _ := json.Marshal(config{Token: strings.Repeat("x", 32), TransportNetwork: network})
		p := t.TempDir() + "/config.json"
		if err := os.WriteFile(p, b, 0600); err != nil {
			t.Fatal(err)
		}
		c, err := loadConfig(p)
		if network == "udp6" {
			if err == nil {
				t.Fatal("invalid transport accepted")
			}
			continue
		}
		if err != nil || (network == "" && c.TransportNetwork != "tcp4") || (network != "" && c.TransportNetwork != network) {
			t.Fatalf("transport config rejected or changed: %s", network)
		}
	}
}

func TestPublicTargetPolicy(t *testing.T) {
	for _, s := range []string{"127.0.0.1", "192.168.1.1", "10.1.2.3", "172.16.1.1", "169.254.169.254", "100.64.1.1", "198.18.0.1", "224.0.0.1", "240.0.0.1", "::1", "fc00::1"} {
		if publicIP(net.ParseIP(s)) {
			t.Fatalf("private/reserved target accepted: %s", s)
		}
	}
	if !publicIP(net.ParseIP("1.1.1.1")) {
		t.Fatal("public target rejected")
	}
	for _, s := range []string{"127.0.0.1:443", "localhost:80", "1.1.1.1:22", "1.1.1.1", "[::1]:80"} {
		v, e := dialPublic(context.Background(), s)
		if e == nil {
			v.Close()
			t.Fatalf("blocked target accepted: %s", s)
		}
	}
}

func TestUpstreamPreferenceRespectsFreshDNS(t *testing.T) {
	ips := []net.IP{net.ParseIP("39.173.161.18"), net.ParseIP("39.173.161.16"), net.ParseIP("39.173.161.17")}
	pref := map[string]string{"cdnfhnfile.115cdn.net": "39.173.161.17"}
	ordered := orderPublicIPs(ips, "CDNFHNFILE.115CDN.NET.", pref)
	if !ordered[0].Equal(ips[2]) || !ordered[1].Equal(ips[0]) || !ordered[2].Equal(ips[1]) || ips[0].String() != "39.173.161.18" {
		t.Fatal("preference changed membership, remaining order, or caller answer")
	}
	for _, p := range []map[string]string{nil, {"cdnfhnfile.115cdn.net": "39.173.161.19"}, {"another.example": "39.173.161.17"}} {
		got := orderPublicIPs(ips, "cdnfhnfile.115cdn.net", p)
		if !got[0].Equal(ips[0]) || len(got) != len(ips) {
			t.Fatal("absent preference must preserve fresh DNS results")
		}
	}
	for _, pref := range []map[string]string{{"cdnfhnfile.115cdn.net": "127.0.0.1"}, {"cdnfhnfile.115cdn.net": "2001:4860::1"}, {"bad host": "39.173.161.17"}, {"CDNFHNFILE.115CDN.NET.": "39.173.161.17"}} {
		c := config{Mode: "server", Token: strings.Repeat("x", 32), PreferredIPv4: pref}
		b, _ := json.Marshal(c)
		path := t.TempDir() + "/config.json"
		if err := os.WriteFile(path, b, 0600); err != nil {
			t.Fatal(err)
		}
		loaded, err := loadConfig(path)
		valid := pref["CDNFHNFILE.115CDN.NET."] != ""
		if valid != (err == nil) {
			t.Fatal("incorrect preference validation")
		}
		if valid && loaded.PreferredIPv4["cdnfhnfile.115cdn.net"] != "39.173.161.17" {
			t.Fatal("host not normalized")
		}
	}
	if conn, err := dialPublicPreferred(context.Background(), "localhost:443", map[string]string{"localhost": "39.173.161.17"}); err == nil {
		conn.Close()
		t.Fatal("preference bypassed private DNS rejection")
	}
}

func TestFallbackSelectionAndPolicy(t *testing.T) {
	c := config{Mode: "client", Token: strings.Repeat("x", 32), TransportNetwork: "tcp", Server: "[2001:4860:4860::8888]:57503", FallbackServer: "58.252.223.164:57503", FallbackLocalFile: "v4"}
	for _, tc := range []struct{ ip, network, server string }{
		{"2001:250:3000::1", "tcp", c.Server},
		{"10.195.75.125", "tcp4", c.FallbackServer},
	} {
		n, s := transportTarget(c, net.ParseIP(tc.ip))
		if n != tc.network || s != tc.server {
			t.Fatalf("incorrect source-family transport: %s %s", n, s)
		}
	}
	for _, server := range []string{"58.252.223.164:57503", "192.168.1.1:57503", "[::1]:57503", "58.252.223.164:0", "58.252.223.164:99999", "example.com:57503"} {
		c.FallbackServer = server
		b, _ := json.Marshal(c)
		p := t.TempDir() + "/config.json"
		if err := os.WriteFile(p, b, 0600); err != nil {
			t.Fatal(err)
		}
		_, err := loadConfig(p)
		if (server == "58.252.223.164:57503") != (err == nil) {
			t.Fatalf("incorrect fallback validation: %s", server)
		}
	}
	p := t.TempDir() + "/local"
	if err := os.WriteFile(p, []byte("invalid\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readLocalAddress(p); err == nil {
		t.Fatal("invalid source accepted")
	}
}
func TestHeaderBound(t *testing.T) {
	var q request
	if readJSONLine(bufio.NewReaderSize(strings.NewReader(strings.Repeat("x", 5000)+"\n"), 4096), &q) == nil {
		t.Fatal("oversize header accepted")
	}
	if readJSONLine(bufio.NewReader(strings.NewReader("{\"token\":\"hello\",\"target\":\"example.com:443\"}\n")), &q) != nil || q.Target != "example.com:443" {
		t.Fatal("valid header failed")
	}
}

func TestHTTPBoundsAndConnectTail(t *testing.T) {
	if _, _, e := readHTTPRequest(bufio.NewReader(strings.NewReader("GET http://example.com/ HTTP/1.1\r\nX: " + strings.Repeat("x", 40000) + "\r\n\r\n"))); e == nil {
		t.Fatal("oversized HTTP header accepted")
	}
	q, r, e := readHTTPRequest(bufio.NewReader(strings.NewReader("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\nTLS")))
	if e != nil || q.Method != "CONNECT" {
		t.Fatal("CONNECT failed")
	}
	b := make([]byte, 3)
	if _, e = r.Read(b); e != nil || string(b) != "TLS" {
		t.Fatal("buffered CONNECT data lost")
	}
}
