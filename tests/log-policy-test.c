#define SCUT_POLICY_UNIT
#include "../tools/log-policy.c"
#include <assert.h>
static unsigned checks;
static void expect(struct policy *p, const char *line, const char *wanted) {
    const char *sev=NULL; size_t n=0; const char *got=classify(p,line,&sev,&n);
    if ((!got)!=(!wanted) || (got && strcmp(got,wanted))) {
        fprintf(stderr,"debug carrier=%ld local=%d have=%d\n",(long)p->carrier,local_ula(p,"fd57:7afa:61f9::1/60"),p->have_ula);
        fprintf(stderr,"failed: wanted=%s got=%s line=%s\n",wanted?wanted:"raw",got?got:"raw",line); exit(1);
    }
    checks++;
}
#define T "Sat Oct 10 "
int main(void) {
    struct policy p={0}; p.old_radio=-1; p.ubi_rom=true; p.have_ula=true;
    struct in6_addr addr; if (inet_pton(AF_INET6,"fd57:7afa:61f9::",&addr)!=1) return 1; memcpy(p.ula,addr.s6_addr,6);
    expect(&p,T"13:00:00 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: stale fd57:7afa:61f9::1/60",NULL);
    expect(&p,T"13:00:00 2026 daemon.notice netifd: bridge 'br-lan' link is down",NULL);
    expect(&p,T"13:00:00 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: stale fd57:7afa:61f9::1/60","info");
    expect(&p,T"13:00:02 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: renew fd57:7afa:61f9::1/60","info");
    expect(&p,T"13:00:00 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: stale 2001:db8::1/60",NULL);
    expect(&p,T"13:00:00 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: stale fd77:7afa:61f9::1/60",NULL);
    expect(&p,T"13:00:06 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: stale fd57:7afa:61f9::1/60",NULL);
    expect(&p,T"13:00:16 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: renew fd57:7afa:61f9::1/60",NULL);
    expect(&p,T"13:00:02 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: renew fd57:7afa:61f9::1/64",NULL);
    expect(&p,T"13:00:02 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: piofile updated","info");
    expect(&p,T"13:00:02 2026 daemon.warn odhcpd[1]: rfc9096: br-lan: piofile update failed",NULL);
    expect(&p,T"13:00:02 2026 daemon.err odhcpd[1]: rfc9096: br-lan: piofile updated",NULL);
    expect(&p,T"13:00:02 2026 daemon.warn odhcpd[1]: DHCPv6 failed",NULL);
    expect(&p,T"13:00:00 2026 kern.alert kernel: [ 1.34] mtdsplit: no squashfs found in \"rootfs\"","info");
    p.ubi_rom=false;
    expect(&p,T"13:00:00 2026 kern.alert kernel: [ 1.34] mtdsplit: no squashfs found in \"rootfs\"",NULL);
    p.ubi_rom=true;
    expect(&p,T"13:00:00 2026 kern.alert kernel: [ 1.34] mtdsplit: no squashfs found in \"rootfs\" I/O error",NULL);
    expect(&p,T"13:00:01 2026 daemon.err procd: Got unexpected signal 1","notice");
    expect(&p,T"13:03:00 2026 daemon.err procd: Got unexpected signal 1",NULL);
    expect(&p,T"13:00:01 2026 daemon.err procd: Got unexpected signal 11",NULL);
    expect(&p,T"13:00:01 2026 daemon.err procd: service crashed",NULL);
    expect(&p,T"13:00:01 2026 daemon.notice netifd: radio2 (2): command failed: Not supported (-95)","debug");
    expect(&p,T"13:03:00 2026 daemon.notice netifd: radio2 (2): command failed: Not supported (-95)",NULL);
    expect(&p,T"13:00:01 2026 cron.err crond[2]: USER root pid 111 cmd /usr/bin/watchdog >/dev/null","info");
    expect(&p,T"13:00:01 2026 cron.err crond[2]: USER root pid invalid cmd /usr/bin/watchdog",NULL);
    expect(&p,T"13:00:01 2026 cron.err crond[2]: can't execute /usr/bin/watchdog",NULL);
    expect(&p,T"13:04:00 2026 user.notice native-best: Disabling radio0",NULL);
    expect(&p,T"13:04:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied",NULL);
    p.absent=1;
    expect(&p,T"13:04:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied","info");
    expect(&p,T"13:04:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/wrong]: Permission denied",NULL);
    expect(&p,T"13:04:01 2026 daemon.notice netifd: wan1 (2): Command failed: ubus call network.interface notify_proto { \"action\": 0, \"link-up\": false, \"keep\": false, \"interface\": \"wan1\" } (Permission denied)","info");
    expect(&p,T"13:04:01 2026 daemon.notice netifd: wan1 (2): Command failed: ubus call network.interface notify_proto { \"action\": 0, \"link-up\": true, \"keep\": false, \"interface\": \"wan1\" } (Permission denied)",NULL);
    expect(&p,T"13:04:21 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied",NULL);
    p.absent=5;
    expect(&p,T"13:04:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied",NULL);
    expect(&p,T"13:04:01 2026 kern.emerg kernel: Kernel panic - not syncing",NULL);
    expect(&p,T"13:04:01 2026 kern.err kernel: UBIFS error",NULL);
    expect(&p,T"13:05:00 2026 user.notice native-best: Enabling candidate radio2",NULL);
    expect(&p,T"13:05:01 2026 daemon.notice netifd: radio2 (2): command failed: Not supported (-95)","debug");
    expect(&p,T"13:05:01 2026 daemon.notice wpa_supplicant[2]: Remove interface phy2-sta0",NULL);
    expect(&p,T"13:05:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied",NULL);
    p.shared_controls=true;
    expect(&p,T"13:05:01 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied","info");
    expect(&p,T"13:05:07 2026 daemon.err wpa_supplicant[2]: rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied",NULL);
    expect(&p,"not a parseable syslog record",NULL);
    printf("ALL %u LOG POLICY CASES PASSED\n",checks); if (checks!=42) return 1;
    return 0;
}
