"""Patch a verified v3.1.3 source tree, then cross-build with a supplied Zig."""
import argparse
import hashlib
from pathlib import Path
import os
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--source', required=True, type=Path)
p.add_argument('--zig', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
for line in (root/'tools/scutclient-v3.1.3.sha256').read_text().splitlines():
    expected, rel = line.split('  ',1)
    if hashlib.sha256((a.source/rel).read_bytes()).hexdigest() != expected:
        raise SystemExit('Upstream source mismatch: '+rel)
auth = a.source / 'src/auth.c'
s = auth.read_text()
if 'wired_begin' in s:
    raise SystemExit('Use a fresh upstream source tree; refusing to patch twice')
s = s.replace('#include "info.h"', '#include "info.h"\nint wired_begin(void);\nint wired_gate(const char*);\nint wired_expired(void);\nint wired_locked(void);\nint wired_renew(void);\nvoid wired_ready(void);\nvoid wired_finish(void);\ntime_t wired_now(void);\nint wired_stopping(void);')
s = s.replace('DRCOM_UDP_HEARTBEAT_TIMEOUT 2', 'DRCOM_UDP_HEARTBEAT_TIMEOUT 5')
s = s.replace('auth_8021x_addr.sll_pkttype = PACKET_HOST;\n\treturn 0;',
              'auth_8021x_addr.sll_pkttype = PACKET_HOST;\n\tif (bind(auth_8021x_sock,(struct sockaddr*)&auth_8021x_addr,sizeof(auth_8021x_addr)) < 0) { ret=-1; goto ERR; }\n\treturn 0;')
s = s.replace('uint8_t recv_8021x_buf[ETH_FRAME_LEN] = { 0 };\n\tif (auth_8021x_Init()',
              'uint8_t recv_8021x_buf[ETH_FRAME_LEN] = { 0 };\n\tret = wired_begin();\n\tif (ret) return ret;\n\tif (auth_8021x_Init()')
s = s.replace('ret = auth_8021x_Logoff();\n\tif (client == LOGOFF)',
              'ret = wired_gate("needs-release");\n\tif (ret == 0) {\n\t\tif (auth_8021x_Logoff() != 1 || wired_gate("released")) { ret=75; goto ERR1; }\n\t} else if (ret != 1) { ret=75; goto ERR1; }\n\tret = wired_gate("journal");\n\tif (ret) goto ERR1;\n\tif (client == LOGOFF)')
s = s.replace('int Authentication(int client) {', (root/'tools/wired-events.inc').read_text() + '\nint Authentication(int client) {')
s = s.replace('while (resev) {', 'while (resev) {\n\t\tif (wired_stopping()) { ret=1; break; }\n\t\tif ((ret=wired_pending_poll()) != 0) break;\n\t\tif (wired_expired()) { ret=1; break; }')
# Clock changes must not extend protocol deadlines/heartbeat waits.
s = s.replace('time(NULL)', 'wired_now()')
s = s.replace('\t\t\texit(EXIT_FAILURE);', '\t\t\treturn 1;')
s = s.replace('while (resev == 0) {', 'while (resev == 0) {\n\t\tif (wired_stopping()) return -EINTR;')
# Keep select wakeups short while there is a challenge pending.
s = s.replace('tmp_timeout = timeout;\n\t\tswitch (select(auth_8021x_sock + auth_udp_sock + 1', 'tmp_timeout = timeout;\n\t\tif (pending_valid) tmp_timeout.tv_sec=1;\n\t\tswitch (select(auth_8021x_sock + auth_udp_sock + 1')
s = s.replace('close(auth_udp_sock);\n\tauth_8021x_Logoff();', 'close(auth_udp_sock);\n\twired_finish();')
s = s.replace('case MISC_HEART_BEAT_04_TYPE:', 'case MISC_HEART_BEAT_04_TYPE:\n\t\t\t\twired_ready();')
s = s.replace('case IDENTITY:\n', 'case IDENTITY:\n\t\t\t{ int admit=wired_challenge_admit(recv_data); if(admit) return admit==77?0:admit; }\n')
s = s.replace('case MD5:\n', 'case MD5:\n\t\t\t{ int admit=wired_challenge_admit(recv_data); if(admit) return admit==77?0:admit; }\n')
s = s.replace('} else if ((EAP_Code) recv_data[18] == SUCCESS) {', '} else if ((EAP_Code) recv_data[18] == SUCCESS) {\n\t\tif (!wired_locked()) return 0;')
# Validate lengths before packet-field access, including variable MD5/notification.
s = s.replace('if (recv_len > 0 && memcmp', 'if (recv_len >= 12 && memcmp')
s = s.replace('&& ((recv_data[0] == 0x07)', '&& clntaddr.sin_port == htons(SERVER_PORT)\n\t\t\t&& ((recv_data[0] == 0x07)')
s = s.replace('PrintHex(DRCOM, "Packet received", recv_data, recv_len);',
              'if (recv_data[0]==0x07 && (recv_data[4]==0x04 || recv_data[4]==0x0b) && recv_len < 32) return 0;')
s = s.replace('if (recv_len > 0\n', 'if (recv_len >= 22\n')
s = s.replace('&& (htons(ETH_P_PAE) == recv_hdr->h_proto)', '&& (htons(ETH_P_PAE) == recv_hdr->h_proto)\n\t\t\t&& (!resev || !memcmp(recv_hdr->h_source,EthHeader,6))')
s = s.replace('PrintHex(DOT1X, "Packet received", recv_data, recv_len);\n\t\treturn 1;',
              'unsigned int len=((unsigned int)recv_data[20]<<8)|recv_data[21];\n\t\tif (len < 4 || len > (unsigned int)recv_len-18 || len >= ETH_FRAME_LEN-18) return 0;\n\t\tif (recv_data[18]==1 && len < 5) return 0;\n\t\tif (recv_data[18]==1 && recv_data[22]==4 && (len < 22 || recv_data[23]!=16)) return 0;\n\t\treturn 1;')
# Raw server notifications can include account information: keep only status.
s = s.replace('"Server: Authentication failed: %s", errstr', '"Server: Authentication failed"')
s = s.replace('"Server: Notification: %s", recv_data + 23', '"Server: Notification received"')
s = s.replace('"%s%s", "Server: Server Information: ", recv_data + 4', '"Server information received"')
s = s.replace('#include "info.h"', '#include "info.h"\n#include <syslog.h>')
start = s.index('int auth_8021x_Logoff() {')
end = s.index('\nint auth_UDP_Init()', start)
s = s[:start] + (root/'tools/wired-logoff.inc').read_text() + s[end:]
s = s.replace('if (auth_8021x_Logoff() != 1 || wired_gate("released")) { ret=75; goto ERR1; }',
              'int released=auth_8021x_Logoff();\n\t\tsyslog(LOG_INFO,"phase=old-session-release confirmed=%d",released==1);\n\t\tif (released != 1 || wired_gate("released")) { ret=75; goto ERR1; }')
s = s.replace('int recv_len = recv(auth_8021x_sock, recv_data, ETH_FRAME_LEN, 0);',
              'int recv_len = recv(auth_8021x_sock, recv_data, ETH_FRAME_LEN, 0);\n\tif (!resev && recv_len >= 22) syslog(LOG_INFO,"phase=eap-receive bytes=%d version=%u type=%u code=%u length=%u",recv_len,recv_data[14],recv_data[15],recv_data[18],((unsigned)recv_data[20]<<8)|recv_data[21]);')
auth.write_text(s)
sources = [a.source/'src'/f'{name}.c' for name in ('auth','drcom','functions','info','md5')]
a.output.parent.mkdir(parents=True,exist_ok=True)
env = {**os.environ, 'ZIG_LOCAL_CACHE_DIR':'/private/tmp/scut-zig-cache',
       'ZIG_GLOBAL_CACHE_DIR':'/private/tmp/scut-zig-global'}
subprocess.run([str(a.zig),'cc','-target','aarch64-linux-musl','-static','-Os','-Wall',
                '-I',str(a.source/'src'),'-o',str(a.output),
                *map(str,sources),str(root/'tools/wired-main.c')],check=True,env=env)
print('sha256',hashlib.sha256(a.output.read_bytes()).hexdigest())
