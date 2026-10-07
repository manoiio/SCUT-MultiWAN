/* Real kernel flock with isolated files; no credentials, sockets or auth. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/file.h>
#include <syslog.h>
#include <string.h>
static char portal[256];
#define WIRED_PORTAL_PATH portal
static int locked, holder=-1, checks, mode, ticks, prepares, stopped;
static time_t deadline, stamp;
time_t wired_now(void) { return stamp; }
int wired_stopping(void) { return stopped; }
static int gate(const char *action) {
    if (!strcmp(action,"preflight")) {
        if (mode==3) return 76;
        if (mode==4 || mode==5) return 75;
        return ((mode==1 && ticks<2) || mode==2) ? 77 : 0;
    }
    prepares++;
    int probe=open(portal,O_WRONLY);
    int held=flock(probe,LOCK_EX|LOCK_NB);
    close(probe);
    if (!locked || held==0) return 98;
    if (mode==6 && prepares==1) return 77;
    if (mode==7) return 76;
    return 0;
}
static unsigned int tick(unsigned int n) {
    ticks++; stamp+=n;
    if (mode==8 && ticks==2) stopped=1;
    if (mode==9 && ticks==2) { close(holder); holder=-1; }
    return 0;
}
#define wired_gate gate
#define sleep tick
#include "../tools/wired-admission.inc"
#undef sleep
#define CHECK(x) do { if(!(x)) {printf("FAIL line %d\n",__LINE__);return 1;} } while(0)
static void reset(int m) {
    if (locked) flock(9,LOCK_UN);
    close(9); if(holder>=0) close(holder);
    locked=0; holder=-1; ticks=0; prepares=0; stopped=0; stamp=100; mode=m;
}
static int lock_holder(void) {
    holder=open(portal,O_WRONLY|O_CREAT,0600);
    return holder>=0 && flock(holder,LOCK_EX|LOCK_NB)==0;
}
int main(int argc,char **argv) {
    if(argc!=2 || strlen(argv[1])>240) return 2;
    snprintf(portal,sizeof(portal),"%s/portal",argv[1]);
    reset(0); CHECK(wired_begin()==0 && prepares==1 && locked); checks++;
    reset(1); CHECK(wired_begin()==0 && ticks==2 && prepares==1); checks++;
    reset(2); CHECK(wired_begin()==75 && ticks==120 && prepares==0 && fcntl(9,F_GETFD)<0); checks++;
    reset(9); CHECK(lock_holder()); CHECK(wired_begin()==0 && ticks==2 && prepares==1); checks++;
    reset(0); CHECK(lock_holder()); CHECK(wired_begin()==75 && ticks==120 && prepares==0); checks++;
    reset(3); CHECK(wired_begin()==76 && prepares==0 && ticks==0); checks++;
    reset(4); CHECK(wired_begin()==75 && prepares==0 && ticks==0); checks++;
    reset(6); CHECK(wired_begin()==0 && prepares==2 && ticks==1); checks++;
    reset(7); CHECK(wired_begin()==76 && prepares==1 && !locked); checks++;
    reset(8); CHECK(lock_holder()); CHECK(wired_begin()==76 && ticks==2 && prepares==0); checks++;
    reset(0); stamp=0; CHECK(wired_begin()==75 && prepares==0); checks++;
    reset(0); unlink(portal);
    printf("ALL %d ADMISSION CHECKS PASSED (real isolated flock; no auth)\n",checks);
    return 0;
}
