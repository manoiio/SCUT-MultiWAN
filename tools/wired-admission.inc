/* AGPL-3.0-or-later. Wait before any authentication packet or durable claim. */
#ifndef WIRED_PORTAL_PATH
#define WIRED_PORTAL_PATH "/tmp/scut-multiwan-locks/portal"
#endif
int wired_begin(void) {
    time_t started = wired_now();
    if (started <= 0) return 75;
    int fd = open(WIRED_PORTAL_PATH, O_WRONLY|O_CREAT, 0600);
    if (fd < 0) return 75;
    if (fd != 9) { if (dup2(fd, 9) < 0) { close(fd); return 75; } close(fd); }
    int reason = 0, rc = 75;
    for (;;) {
        time_t now = wired_now();
        if (wired_stopping()) { rc = 76; break; }
        if (now < started || now-started >= 120) {
            syslog(LOG_INFO,"phase=admission timeout reason=%s",reason==77?"interface":"portal-lock");
            rc = 75; break;
        }
        rc = wired_gate("preflight");
        if (rc != 0 && rc != 77) {
            syslog(LOG_INFO,"phase=preflight rejected code=%d",rc); break;
        }
        if (rc == 0 && flock(9, LOCK_EX|LOCK_NB) == 0) {
            locked = 1;
            rc = wired_gate("prepare");
            if (rc == 0) {
                deadline = wired_now()+45;
                syslog(LOG_INFO,"phase=admission ready waited=%ld",(long)(wired_now()-started));
                return 0;
            }
            flock(9, LOCK_UN); locked = 0;
            if (rc != 77) {
                syslog(LOG_INFO,"phase=prepare rejected code=%d",rc); break;
            }
        } else if (rc == 0 && errno != EWOULDBLOCK && errno != EAGAIN) {
            syslog(LOG_INFO,"phase=admission lock-error"); rc = 75; break;
        }
        int next = rc==77 ? 77 : 75;
        if (next != reason) {
            syslog(LOG_INFO,"phase=admission waiting reason=%s",next==77?"interface":"portal-lock");
            reason = next;
        }
        sleep(1);
    }
    close(9);
    return rc;
}
