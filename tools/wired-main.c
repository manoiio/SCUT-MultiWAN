/* SCUT-MultiWAN adapter for scutclient v3.1.3 (AGPL-3.0-or-later).
 * Credentials arrive on stdin. One attempt per process; policy owns retries.
 */
#include "auth.h"
#include "tracelog.h"
#include <signal.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>

static int locked;
static time_t deadline;
static char user[33], pass[112];
static volatile sig_atomic_t stopping;
static int singleton = -1, announced;
time_t wired_now(void) {
    struct timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) == 0 ? ts.tv_sec : 0;
}
int wired_stopping(void) { return stopping; }

int wired_gate(const char *action) {
    char cmd[160];
    snprintf(cmd, sizeof(cmd), "/usr/bin/scut-wired-gate %s", action);
    int rc = system(cmd);
    return rc >= 0 && WIFEXITED(rc) ? WEXITSTATUS(rc) : 75;
}

#include "wired-admission.inc"

int wired_expired(void) { return locked && wired_now() >= deadline; }
int wired_locked(void) { return locked; }

int wired_renew(void) {
    if (locked) return 0;
    int fd=open("/tmp/scut-multiwan-locks/portal",O_WRONLY);
    if (fd<0) return 75;
    if (fd!=9) { if (dup2(fd,9)<0) { close(fd); return 75; } close(fd); }
    if (flock(9,LOCK_EX|LOCK_NB)) { close(9); return 75; }
    locked=1;
    int rc=wired_gate("challenge");
    if (rc) { flock(9,LOCK_UN); close(9); locked=0; return rc; }
    deadline=wired_now()+45;
    syslog(LOG_INFO,"existing-session server challenge admitted");
    return 0;
}

static void refresh_routes(void) {
    /* Route checks are independent of the heartbeat loop. */
    pid_t pid = fork();
    if (pid == 0) {
        if (fork() != 0) _exit(0);
        setsid();
        /* Route helpers must not keep the engine/socket/transaction alive. */
        for (int fd=3; fd<64; fd++) close(fd);
        execl("/usr/bin/dualwan-refresh", "dualwan-refresh", "force", (char*)NULL);
        _exit(1);
    }
    if (pid > 0) waitpid(pid, NULL, 0);
}

void wired_ready(void) {
    if (!locked) return;
    char action[64];
    snprintf(action,sizeof(action),"ready %ld",(long)getpid());
    if (wired_gate(action)) return;
    syslog(LOG_INFO,"UDP heartbeat complete; existing session maintained");
    flock(9, LOCK_UN); close(9); locked = 0;
    if (!announced) { announced=1; refresh_routes(); }
}

void wired_finish(void) {
    /* Remove volatile readiness even if release must defer; retain journal. */
    unlink("/tmp/scut-wired-ready");
    if (!locked) {
        int fd = open("/tmp/scut-multiwan-locks/portal", O_WRONLY);
        if (fd < 0) return;
        if (fd != 9) { if (dup2(fd,9) < 0) { close(fd); return; } close(fd); }
        if (flock(9, LOCK_EX|LOCK_NB)) { close(9); return; }
        locked = 1;
    }
    if (!wired_gate("cleanup") && auth_8021x_Logoff() == 1)
        wired_gate("released");
    else wired_gate("uncertain");
    flock(9, LOCK_UN); close(9); locked = 0;
}

static void terminate(int sig) { (void)sig; stopping=1; }

static int read_secret(char *buf, size_t size) {
    if (!fgets(buf, size, stdin)) return 1;
    char *nl = strchr(buf, '\n');
    if (!nl) return 1;
    *nl = 0;
    return !buf[0];
}

static int release_only(void) {
    int singleton=open("/tmp/scut-multiwan-locks/wired-engine",O_WRONLY|O_CREAT,0600);
    if (singleton < 0 || flock(singleton,LOCK_EX|LOCK_NB)) return 75;
    int fd=open("/tmp/scut-multiwan-locks/portal",O_WRONLY|O_CREAT,0600);
    if (fd < 0) return 75;
    if (fd != 9) { if (dup2(fd,9)<0) { close(fd); return 75; } close(fd); }
    if (flock(9,LOCK_EX|LOCK_NB)) return 75;
    locked=1;
    int rc=wired_gate("cleanup");
    if (rc) return rc;
    rc=wired_gate("needs-release");
    if (rc==1) return 0;
    if (rc) return rc;
    strncpy(DeviceName,"wan",sizeof(DeviceName)-1);
    if (auth_8021x_Init()) return 75;
    initAuthenticationInfo();
    if (auth_8021x_Logoff()==1) return wired_gate("released");
    wired_gate("uncertain");
    return 75;
}

int main(int argc, char **argv) {
    openlog("scut-wired",LOG_PID,LOG_DAEMON);
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts("scutclient 3.1.3 + SCUT-MultiWAN guarded single-attempt adapter");
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--release")) return release_only();
    if (argc != 5 || strlen(argv[1]) >= IFNAMSIZ || read_secret(user,sizeof(user)) ||
        read_secret(pass,sizeof(pass))) return 2;
    UserName = user; Password = pass;
    strncpy(DeviceName,argv[1],IFNAMSIZ-1);
    if (!inet_aton(argv[2],&udpserver_ipaddr) || !inet_aton(argv[3],&dns_ipaddr)) return 2;
    strncpy(HostName,argv[4],sizeof(HostName)-1);
    signal(SIGTERM,terminate); signal(SIGINT,terminate);
    singleton = open("/tmp/scut-multiwan-locks/wired-engine",O_WRONLY|O_CREAT,0600);
    if (singleton < 0 || flock(singleton,LOCK_EX|LOCK_NB)) return 75;
    int rc = Authentication(1);
    syslog(LOG_INFO,"attempt exited code=%d",rc);
    close(9);
    refresh_routes();
    memset(pass,0,sizeof(pass));
    return rc == 75 || rc == 76 ? rc : (rc ? 1 : 0);
}

/* Never expand arbitrary server text or dump authentication packets. */
LOGLEVEL cloglev = INF;
int LogWrite(LOGTYPE type, LOGLEVEL level, char *format, ...) {
    if (level == ERROR || (type==DRCOM && locked && level==INF) || strstr(format,"Server: Success") ||
        strstr(format,"Request Identity") || strstr(format,"MD5-Challenge")) {
        openlog("scut-wired",LOG_PID,LOG_DAEMON);
        syslog(level == ERROR ? LOG_ERR : LOG_INFO,"stage=%d %s",type,format);
    }
    return 0;
}
