/* A presentation policy over ubox logread. The logd/ubus stream stays raw.
 * Never discard a message. File mode retains a separate, bounded raw copy.
 * No authentication, network reconfiguration or logd replacement here. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SCUT_LOGREAD_BACKEND
#define SCUT_LOGREAD_BACKEND "/usr/libexec/logread-ubox"
#endif
struct policy {
    bool ubi_rom;
    unsigned char ula[6];
    bool have_ula;
    time_t real_boot, stream_boot, carrier, stale, transition, remove_interface;
    char stale_prefix[80];
    int old_radio;
    unsigned absent; /* tests inject this; production refreshes from sysfs */
    bool shared_controls;
};
static bool between(time_t now, time_t before, int seconds) {
    return before > 0 && now >= before && now-before <= seconds;
}
static time_t line_time(const char *line, const char **rest) {
    struct tm tm = {0};
    char *end = strptime(line, "%a %b %e %H:%M:%S %Y ", &tm);
    if (!end) return 0;
    tm.tm_isdst = -1;
    *rest = end;
    return mktime(&tm);
}
static void load_policy(struct policy *p) {
    memset(p, 0, sizeof(*p));
    p->old_radio = -1;
    /* Static musl uses /etc/localtime; OpenWrt commonly stores /etc/TZ instead. */
    char timezone[128]; FILE *tz=fopen("/etc/TZ","r");
    if (tz) {
        if (fgets(timezone,sizeof(timezone),tz)) {
            timezone[strcspn(timezone,"\r\n")]=0;
            if (*timezone) setenv("TZ",timezone,1);
        }
        fclose(tz);
    }
    tzset();
    FILE *f = fopen("/proc/uptime", "r"); double up;
    if (f) { if (fscanf(f, "%lf", &up)==1) p->real_boot=time(NULL)-(time_t)up; fclose(f); }
    char line[1024]; bool mounted=false, block=false;
    f=fopen("/proc/mounts", "r");
    if (f) { while (fgets(line,sizeof(line),f)) if (strstr(line," /rom squashfs ")) mounted=true; fclose(f); }
    f=fopen("/proc/cmdline", "r");
    if (f) { if (fgets(line,sizeof(line),f)) block=strstr(line,"ubi.block=") && strstr(line,"root=/dev/ubiblock"); fclose(f); }
    p->ubi_rom=mounted && block;
    f=fopen("/etc/config/network", "r");
    if (f) {
        while (fgets(line,sizeof(line),f)) {
            char key[80], val[128]; struct in6_addr addr;
            if (sscanf(line," option %79s %127s",key,val)!=2 || strcmp(key,"ula_prefix")) continue;
            char *start=val; if (*start=='\'' || *start=='"') start++;
            char *end=strchr(start,'/'); if (end) *end=0;
            if (inet_pton(AF_INET6,start,&addr)==1 && (addr.s6_addr[0]&0xfe)==0xfc) {
                memcpy(p->ula,addr.s6_addr,6); p->have_ula=true;
            }
        }
        fclose(f);
    }
}
static void refresh_interfaces(struct policy *p) {
    /* The first boot-time NTP step may move the wall clock by hours. */
    FILE *clock=fopen("/proc/uptime","r"); double up;
    if (clock) { if (fscanf(clock,"%lf",&up)==1) p->real_boot=time(NULL)-(time_t)up; fclose(clock); }
    p->absent=0;
    if (access("/sys/class/net/phy0-sta0",F_OK)!=0 && errno==ENOENT) p->absent|=1;
    if (access("/sys/class/net/phy2-sta0",F_OK)!=0 && errno==ENOENT) p->absent|=4;
    struct stat global, usb, native;
    p->shared_controls=stat("/var/run/wpa_supplicant/global",&global)==0 && S_ISSOCK(global.st_mode) &&
        stat("/var/run/wpa_supplicant/phy3-sta0",&usb)==0 && S_ISSOCK(usb.st_mode) &&
        ((stat("/var/run/wpa_supplicant/phy0-sta0",&native)==0 && S_ISSOCK(native.st_mode)) ||
         (stat("/var/run/wpa_supplicant/phy2-sta0",&native)==0 && S_ISSOCK(native.st_mode)));
}
static bool local_ula(struct policy *p, const char *prefix) {
    char buf[80]; struct in6_addr addr;
    if (strlen(prefix)>=sizeof(buf)) return false;
    strcpy(buf,prefix); char *end=strchr(buf,'/');
    if (!end || strcmp(end,"/60")) return false;
    *end=0;
    return p->have_ula && inet_pton(AF_INET6,buf,&addr)==1 && !memcmp(p->ula,addr.s6_addr,6);
}
/* Returns a replacement severity, or NULL to preserve the raw line. */
static const char *classify(struct policy *p, const char *line, const char **severity, size_t *len) {
    const char *rest=NULL; time_t now=line_time(line,&rest);
    if (!now || !rest) return NULL;
    const char *dot=strchr(rest,'.'), *space=strchr(rest,' ');
    if (!dot || !space || dot>space) return NULL;
    *severity=dot+1; *len=(size_t)(space-dot-1);
    const char *body=space+1;
    char message[4096]; size_t n=strcspn(body,"\r\n");
    if (n>=sizeof(message)) return NULL;
    memcpy(message,body,n); message[n]=0;
    body=message;
    double kernel_up;
    if (!strncmp(body,"kernel: [",9) && sscanf(body,"kernel: [ %lf]",&kernel_up)==1 && kernel_up<120)
        p->stream_boot=now-(time_t)kernel_up;
    if (strstr(body,"kernel: ") && strstr(body,"lan2: PHY Link is Down")) p->carrier=now;
    if (!strcmp(body,"netifd: bridge 'br-lan' link is down")) p->carrier=now;
    if (!strcmp(body,"netifd: Network device 'br-lan' link is down")) p->carrier=now;
    int radio;
    if (sscanf(body,"native-best: Enabling candidate radio%d",&radio)==1 && (radio==0 || radio==2)) {
        p->transition=now; p->old_radio=-1;
    }
    if (!strncmp(body,"wpa_supplicant[",15)) {
        const char *m=strstr(body,"]: Remove interface phy");
        if (m && (!strcmp(m,"]: Remove interface phy0-sta0") || !strcmp(m,"]: Remove interface phy2-sta0"))) p->remove_interface=now;
    }
    if (sscanf(body,"native-best: Disabling radio%d",&radio)==1 && (radio==0 || radio==2)) {
        p->transition=now; p->old_radio=radio;
    }
    /* Do not downgrade critical/emergency records from unexpected producers. */
    if (!strncmp(rest,"cron.err ",9) && !strncmp(body,"crond[",6)) {
        const char *m=strstr(body,"]: USER root pid "); unsigned pid; int used=0;
        if (m && sscanf(m,"]: USER root pid %u cmd %n",&pid,&used)==1 && used>0 && m[used]) return "info";
    }
    if (!strncmp(rest,"daemon.warn ",12) && !strncmp(body,"odhcpd[",7)) {
        const char *m=strstr(body,"]: rfc9096: br-lan: ");
        if (m) {
            m+=strlen("]: rfc9096: br-lan: ");
            if (!strcmp(m,"piofile updated")) return "info";
            if (!strncmp(m,"stale ",6) && local_ula(p,m+6) && between(now,p->carrier,5)) {
                p->stale=now; snprintf(p->stale_prefix,sizeof(p->stale_prefix),"%s",m+6); return "info";
            }
            if (!strncmp(m,"renew ",6) && between(now,p->stale,15) && !strcmp(m+6,p->stale_prefix)) return "info";
        }
    }
    const char *kernel_message=strstr(body,"] ");
    if (!strncmp(rest,"kern.alert ",11) && p->ubi_rom &&
        !strncmp(body,"kernel: [",9) && kernel_message && !strcmp(kernel_message+2,"mtdsplit: no squashfs found in \"rootfs\"") &&
        sscanf(body,"kernel: [ %lf]",&kernel_up)==1 && kernel_up<10) return "info";
    if (!strncmp(rest,"daemon.err ",11) && !strcmp(body,"procd: Got unexpected signal 1") &&
        (between(now,p->real_boot,120) || between(now,p->stream_boot,120))) return "notice";
    bool teardown=between(now,p->transition,20) && p->old_radio>=0 &&
        (p->absent & (1u<<p->old_radio)) && (p->absent & 5)!=5;
    /* rmdir of a shared parent is harmless when live peers still own sockets.
     * This does not excuse failure to stop a WAN/association (checked above). */
    if ((teardown || (p->shared_controls && between(now,p->remove_interface,5))) &&
        !strncmp(rest,"daemon.err ",11) && !strncmp(body,"wpa_supplicant[",15)) {
        const char *m=strstr(body,"]: ");
        if (m && !strcmp(m+3,"rmdir[ctrl_interface=/var/run/wpa_supplicant]: Permission denied")) return "info";
    }
    if (teardown && !strncmp(rest,"daemon.notice ",14) && !strncmp(body,"netifd: ",8)) {
        char expected[256];
        snprintf(expected,sizeof(expected),"Command failed: ubus call network.interface notify_proto { \"action\": 0, \"link-up\": false, \"keep\": false, \"interface\": \"wan%d\" } (Permission denied)",p->old_radio==0?1:2);
        const char *m=strstr(body,"): ");
        if (m && !strcmp(m+3,expected)) return "info";
    }
    if (!strncmp(rest,"daemon.notice ",14) && !strncmp(body,"netifd: radio",13)) {
        const char *m=strstr(body,"): ");
        if (m && !strcmp(m+3,"command failed: Not supported (-95)") &&
            (between(now,p->real_boot,120) || between(now,p->stream_boot,120) || between(now,p->transition,20))) return "debug";
    }
    return NULL;
}
static int write_line(FILE *out, struct policy *p, const char *line) {
    const char *sev=NULL; size_t len=0; const char *replacement=classify(p,line,&sev,&len);
    if (!replacement) return fputs(line,out)==EOF ? -1 : 0;
    if (fwrite(line,1,(size_t)(sev-line),out)!=(size_t)(sev-line) || fputs(replacement,out)==EOF || fputs(sev+len,out)==EOF) return -1;
    return 0;
}

#ifndef SCUT_POLICY_UNIT
static volatile sig_atomic_t stopping;
static volatile sig_atomic_t child_pid;
static void stop_child(int sig) { stopping=sig; if (child_pid>0) kill(child_pid,sig); }
static int append_line(const char *path, size_t limit, struct policy *p, const char *line, bool raw) {
    struct stat st;
    if (stat(path,&st)==0 && (size_t)st.st_size>limit) {
        char old[4096]; if (snprintf(old,sizeof(old),"%s.old",path)>=(int)sizeof(old)) return -1;
        if (rename(path,old)!=0) return -1;
    }
    int fd=open(path,O_WRONLY|O_APPEND|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600);
    if (fd<0) return -1;
    if (fchmod(fd,0600)!=0) { close(fd); return -1; }
    FILE *out=fdopen(fd,"a"); if (!out) { close(fd); return -1; }
    int rc=raw ? (fputs(line,out)==EOF ? -1:0) : write_line(out,p,line);
    if (fflush(out)!=0 || fsync(fd)!=0) rc=-1;
    if (fclose(out)!=0) rc=-1;
    return rc;
}
int main(int argc, char **argv) {
    umask(077);
    struct policy p; load_policy(&p);
    if (argc==2 && !strcmp(argv[1],"--classify")) {
        char *line=NULL; size_t cap=0; int rc=0;
        while (getline(&line,&cap,stdin)>0) { refresh_interfaces(&p); if (write_line(stdout,&p,line)!=0) { rc=1; break; } }
        if (ferror(stdin) || fflush(stdout)!=0) rc=1;
        free(line); return rc;
    }
    char **args=calloc((size_t)argc+2,sizeof(char*)); if (!args) return 1;
    args[0]=SCUT_LOGREAD_BACKEND; int used=1; const char *file=NULL,*pidfile=NULL; size_t limit=2097152;
    bool raw=false, remote=false;
    for (int i=1;i<argc;i++) if (!strcmp(argv[i],"--raw")) raw=true; else if (!strcmp(argv[i],"-r")) remote=true;
    if (raw || remote) {
        for (int i=1;i<argc;i++) if (strcmp(argv[i],"--raw")) args[used++]=argv[i];
        execv(args[0],args); perror("scut-logread backend"); return 1;
    }
    for (int i=1;i<argc;i++) {
        if (!strcmp(argv[i],"-F") && i+1<argc) file=argv[++i];
        else if (!strcmp(argv[i],"-p") && i+1<argc) pidfile=argv[++i];
        else if (!strcmp(argv[i],"-S") && i+1<argc) {
            char *end; unsigned long kib=strtoul(argv[++i],&end,10);
            if (*end || kib==0 || kib>16384) { fprintf(stderr,"invalid log size\n"); return 2; }
            limit=(size_t)kib*1024;
        } else args[used++]=argv[i];
    }
    char rawfile[4096];
    if (file && (snprintf(rawfile,sizeof(rawfile),"%s",!strcmp(file,"/etc/scut-logs/system.log")?"/etc/scut-logs/raw.log":"")>=(int)sizeof(rawfile))) return 2;
    if (file && !rawfile[0] && snprintf(rawfile,sizeof(rawfile),"%s.raw",file)>=(int)sizeof(rawfile)) return 2;
    int pipes[2]; if (pipe(pipes)!=0) return 1;
    struct sigaction sa={0}; sa.sa_handler=stop_child; sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM,&sa,NULL); sigaction(SIGINT,&sa,NULL); sigaction(SIGHUP,&sa,NULL);
    signal(SIGPIPE,SIG_IGN);
    pid_t pid=fork(); if (pid<0) return 1;
    if (pid==0) {
        signal(SIGTERM,SIG_DFL); signal(SIGINT,SIG_DFL); signal(SIGHUP,SIG_DFL); signal(SIGPIPE,SIG_DFL);
        dup2(pipes[1],STDOUT_FILENO); close(pipes[0]); close(pipes[1]);
        execv(args[0],args); perror("scut-logread backend"); _exit(127);
    }
    child_pid=pid; close(pipes[1]);
    int rc=0;
    if (pidfile) {
        int fd=open(pidfile,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC|O_NOFOLLOW,0600);
        if (fd<0 || dprintf(fd,"%ld\n",(long)getpid())<0) rc=1;
        if (fd>=0) close(fd);
    }
    FILE *in=fdopen(pipes[0],"r"); char *line=NULL; size_t cap=0;
    if (!in) rc=1;
    while (!rc && !stopping && getline(&line,&cap,in)>0) {
        refresh_interfaces(&p);
        if (file) {
            /* Raw first: even a presentation-write failure preserves evidence. */
            if (append_line(rawfile,limit,&p,line,true)!=0 || append_line(file,limit,&p,line,false)!=0) rc=1;
        } else if (write_line(stdout,&p,line)!=0 || fflush(stdout)!=0) rc=1;
    }
    if (in && ferror(in) && !stopping) rc=1;
    if (in) fclose(in); else close(pipes[0]); free(line); free(args);
    if (rc || stopping) kill(pid,SIGTERM);
    int status=0; while (waitpid(pid,&status,0)<0 && errno==EINTR) {}
    child_pid=0;
    if (pidfile) {
        FILE *f=fopen(pidfile,"r"); long owner=0;
        if (f) { if (fscanf(f,"%ld",&owner)==1 && owner==(long)getpid()) unlink(pidfile); fclose(f); }
    }
    if (rc) { fprintf(stderr,"scut-logread: stream/write failed; raw evidence retained where possible\n"); return rc; }
    return stopping ? 0 : WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
#endif
