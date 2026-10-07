/* AGPL-3.0-or-later. Pure packet/guard tests; no real sockets are opened. */
#include "auth.h"
#include "tracelog.h"
static int locked, renew_rc, renew_calls, sends, ready_calls;
static unsigned char frame[ETH_FRAME_LEN];
static int frame_len, peer_port=61440;
static time_t mock_now=100;
static int stopping, checks;
static int logoff_mode, broadcast_sends, start_sends, target_sends, credential_sends;
time_t wired_now(void) { return mock_now; }
int wired_stopping(void) { return stopping; }
int wired_pending_poll(void);
LOGLEVEL cloglev=NONE;
void syslog(int priority,const char *format,...) { (void)priority;(void)format; }
int LogWrite(LOGTYPE t,LOGLEVEL l,char *f,...) { (void)t;(void)l;(void)f;return 0; }
int wired_begin(void) { return 0; }
int wired_gate(const char *a) { (void)a;return 0; }
int wired_expired(void) { return 0; }
int wired_locked(void) { return locked; }
int wired_renew(void) { renew_calls++; if(!renew_rc) locked=1; return renew_rc; }
void wired_ready(void) { ready_calls++;locked=0; }
void wired_finish(void) {}
ssize_t sendto(int s,const void *b,size_t n,int f,const struct sockaddr *a,socklen_t l) {
    (void)s;(void)f;(void)a;(void)l;sends++;
    const unsigned char *p=b;
    if (n>=18 && p[12]==0x88 && p[13]==0x8e) {
        if (p[15]==1) start_sends++;
        if (p[15]==2 && p[0]==0xff) broadcast_sends++;
        if (p[15]==2 && p[0]==2) target_sends++;
        if (p[15]==0 && p[18]==2) credential_sends++;
    }
    return n;
}
int select(int n,fd_set *r,fd_set *w,fd_set *e,struct timeval *t) {
    (void)n;(void)r;(void)w;(void)e;(void)t;
    mock_now++;
    if (logoff_mode>=5) {
        if (!start_sends) return 0;
        memset(frame,0,sizeof(frame));frame[12]=0x88;frame[13]=0x8e;
        frame[6]=2;frame[18]=1;frame[21]=5;frame[22]=1;frame_len=23;
        if (target_sends) { frame[18]=4;frame[21]=4;frame_len=22; }
        if (logoff_mode==6 && target_sends) return 0;
        if (logoff_mode==7 && target_sends) frame[6]=4;
        return 1;
    }
    if (logoff_mode && broadcast_sends) {
        memset(frame,0,sizeof(frame));frame[12]=0x88;frame[13]=0x8e;
        frame[18]=4;frame[21]=4;frame_len=22;
        if (logoff_mode==2) frame[21]=20;
        if (logoff_mode==3) frame[0]=1;
        if (logoff_mode==4) frame[15]=1;
        return 1;
    }
    return 0;
}
ssize_t recv(int s,void *b,size_t n,int f) {
    (void)s;(void)n;(void)f;memcpy(b,frame,frame_len);return frame_len;
}
ssize_t recvfrom(int s,void *b,size_t n,int f,struct sockaddr *a,socklen_t *l) {
    (void)s;(void)n;(void)f;struct sockaddr_in *p=(struct sockaddr_in*)a;
    memset(p,0,sizeof(*p));p->sin_port=htons(peer_port);*l=sizeof(*p);
    memcpy(b,frame,frame_len);return frame_len;
}
static void reset(void) { locked=0;renew_rc=0;renew_calls=0;sends=0;broadcast_sends=0;start_sends=0;target_sends=0;credential_sends=0;memset(frame,0,sizeof(frame)); }
#define CHECK(x) do { checks++; if(!(x)) { printf("FAIL line %d\n",__LINE__);return 1; } } while(0)
int main(void) {
    unsigned char packet[ETH_FRAME_LEN]={0};
    UserName="fixture-user";Password="fixture-password";
    reset();frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==0 && renew_calls==1 && sends==1);
    reset();renew_rc=76;frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==76 && renew_calls==1 && sends==0);
    reset();renew_rc=75;frame[18]=1;frame[21]=22;frame[22]=4;frame[23]=16;
    CHECK(auth_8021x_Handler(frame)==0 && renew_calls==1 && sends==0);
    CHECK(wired_pending_poll()==0 && sends==0);
    renew_rc=0;
    CHECK(wired_pending_poll()==0 && sends==1 && locked);
    reset();renew_rc=75;frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==0 && sends==0);
    mock_now+=15;
    CHECK(wired_pending_poll()==0 && sends==0);
    mock_now+=44;
    CHECK(wired_pending_poll()==0 && sends==0);
    renew_rc=0;CHECK(wired_pending_poll()==0 && sends==1);
    reset();renew_rc=75;frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==0 && sends==0);
    mock_now+=119;
    CHECK(wired_pending_poll()==0 && sends==0);
    /* Repeated server requests cannot extend the original wait deadline. */
    CHECK(auth_8021x_Handler(frame)==0 && sends==0);
    mock_now+=1;
    CHECK(wired_pending_poll()==76 && sends==0);
    renew_rc=0;mock_now-=120;CHECK(wired_pending_poll()==0 && sends==1);
    reset();frame[18]=3;frame[21]=4;
    CHECK(auth_8021x_Handler(frame)==0 && sends==0);
    reset();locked=1;frame[18]=3;frame[21]=4;
    CHECK(auth_8021x_Handler(frame)==0 && sends==1);
    reset();locked=1;frame[0]=7;frame[4]=0x0b;frame[5]=4;
    CHECK(Drcom_UDP_Handler(frame)==0 && ready_calls==1 && !locked);
    reset();frame[12]=0x88;frame[13]=0x8e;frame[18]=3;frame[21]=4;frame_len=22;
    CHECK(auth_8021x_Receiver(packet)==1);
    frame_len=20;CHECK(auth_8021x_Receiver(packet)==0);
    frame_len=22;frame[18]=1;frame[21]=5;CHECK(auth_8021x_Receiver(packet)==0);
    frame_len=24;frame[21]=6;frame[22]=4;frame[23]=1;CHECK(auth_8021x_Receiver(packet)==0);
    reset();frame[0]=7;frame[4]=2;frame_len=16;CHECK(auth_UDP_Receiver(packet)==1);
    frame[4]=4;CHECK(auth_UDP_Receiver(packet)==0);
    frame[4]=0x0b;frame_len=32;CHECK(auth_UDP_Receiver(packet)==1);
    peer_port=61441;CHECK(auth_UDP_Receiver(packet)==0);
    reset();broadcast_sends=0;start_sends=0;logoff_mode=0;
    initAuthenticationInfo();
    int lr=auth_8021x_Logoff();
    CHECK(lr==0 && sends==2 && broadcast_sends==1 && start_sends==0);
    reset();broadcast_sends=0;logoff_mode=1;
    CHECK(auth_8021x_Logoff()==1 && sends==2 && broadcast_sends==1 && start_sends==0);
    reset();broadcast_sends=0;logoff_mode=2;
    CHECK(auth_8021x_Logoff()==0 && start_sends==0);
    reset();locked=1;broadcast_sends=0;start_sends=0;target_sends=0;credential_sends=0;logoff_mode=5;
    CHECK(auth_8021x_Logoff()==1 && target_sends==1 && start_sends==1 && credential_sends==0);
    reset();locked=1;broadcast_sends=0;start_sends=0;target_sends=0;logoff_mode=6;
    CHECK(auth_8021x_Logoff()==0 && target_sends==1 && credential_sends==0);
    reset();locked=1;broadcast_sends=0;start_sends=0;target_sends=0;logoff_mode=7;
    CHECK(auth_8021x_Logoff()==0 && target_sends==1 && credential_sends==0);
    reset();broadcast_sends=0;logoff_mode=3;
    CHECK(auth_8021x_Logoff()==0 && start_sends==0);
    reset();broadcast_sends=0;logoff_mode=4;
    CHECK(auth_8021x_Logoff()==0 && start_sends==0);
    printf("ALL %d PROTOCOL CHECKS PASSED (including deferred lock/timeout; no network operations)\n", checks);
    return 0;
}
