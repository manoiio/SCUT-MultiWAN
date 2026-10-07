// Probe only the public tunnel preamble and pinned TLS certificate; no auth/CDN.
package main
import("context";"crypto/sha256";"crypto/tls";"crypto/x509";"encoding/hex";"encoding/json";"flag";"fmt";"io";"net";"os";"strings";"syscall";"time")
func main(){
 ips:=flag.String("ips","","comma separated public IPv4 addresses"); devs:=flag.String("devices","phy2-sta0,phy3-sta0,wan","interfaces"); ca:=flag.String("ca","/etc/scut-bond/server.crt","trusted certificate"); flag.Parse()
 pem,e:=os.ReadFile(*ca); if e!=nil{panic("CA unavailable")}; roots:=x509.NewCertPool(); if !roots.AppendCertsFromPEM(pem){panic("CA invalid")}
 for _,dev:=range strings.Split(*devs,",") { iface,e:=net.InterfaceByName(dev);if e!=nil{continue};addrs,_:=iface.Addrs();var local net.IP;for _,a:=range addrs{ip,_,_:=net.ParseCIDR(a.String());if ip.To4()!=nil{local=ip.To4();break}};if local==nil{continue}
 for _,ip:=range strings.Split(*ips,","){for trial:=1;trial<=2;trial++{
  start:=time.Now();r:=map[string]any{"device":dev,"destination":ip,"trial":trial};
  d:=net.Dialer{Timeout:2*time.Second,LocalAddr:&net.TCPAddr{IP:local},Control:func(_, _ string,c syscall.RawConn)error{var err error;e:=c.Control(func(fd uintptr){err=syscall.SetsockoptString(int(fd),syscall.SOL_SOCKET,syscall.SO_BINDTODEVICE,dev)});if e!=nil{return e};return err}};d.SetMultipathTCP(true)
  raw,e:=d.DialContext(context.Background(),"tcp4",net.JoinHostPort(ip,"57501"));r["connect_ms"]=float64(time.Since(start).Microseconds())/1000
  if e==nil{active,_:=raw.(*net.TCPConn).MultipathTCP();r["mptcp"]=active;raw.SetDeadline(time.Now().Add(2*time.Second));_,e=io.WriteString(raw,"SCUTB1\r\n");b:=make([]byte,8);if e==nil{_,e=io.ReadFull(raw,b)};if e==nil&&string(b)!="SCUTB1\r\n"{e=fmt.Errorf("preamble mismatch")};if e==nil{t:=tls.Client(raw,&tls.Config{RootCAs:roots,ServerName:"scut-bond-vps",MinVersion:tls.VersionTLS13});e=t.Handshake();if e==nil{sum:=sha256.Sum256(t.ConnectionState().PeerCertificates[0].Raw);r["certificate_sha256"]=hex.EncodeToString(sum[:])}};raw.Close()}
  r["elapsed_ms"]=float64(time.Since(start).Microseconds())/1000;r["ok"]=e==nil;if e!=nil{r["error_type"]=fmt.Sprintf("%T",e)};json.NewEncoder(os.Stdout).Encode(r)
 }}
 }
}
