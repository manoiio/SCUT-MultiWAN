/* AGPL-3.0-or-later. Pure packet/guard tests; no real sockets are opened. */
#include "auth.h"
#include "tracelog.h"
static int locked, renew_rc, renew_calls, sends, ready_calls;
static unsigned char frame[ETH_FRAME_LEN];
static int frame_len, peer_port=61440;
LOGLEVEL cloglev=NONE;
int LogWrite(LOGTYPE t,LOGLEVEL l,char *f,...) { (void)t;(void)l;(void)f;return 0; }
int wired_begin(void) { return 0; }
int wired_gate(const char *a) { (void)a;return 0; }
int wired_expired(void) { return 0; }
int wired_locked(void) { return locked; }
int wired_renew(void) { renew_calls++; if(!renew_rc) locked=1; return renew_rc; }
void wired_ready(void) { ready_calls++;locked=0; }
void wired_finish(void) {}
ssize_t sendto(int s,const void *b,size_t n,int f,const struct sockaddr *a,socklen_t l) {
    (void)s;(void)b;(void)f;(void)a;(void)l;sends++;return n;
}
ssize_t recv(int s,void *b,size_t n,int f) {
    (void)s;(void)n;(void)f;memcpy(b,frame,frame_len);return frame_len;
}
ssize_t recvfrom(int s,void *b,size_t n,int f,struct sockaddr *a,socklen_t *l) {
    (void)s;(void)n;(void)f;struct sockaddr_in *p=(struct sockaddr_in*)a;
    memset(p,0,sizeof(*p));p->sin_port=htons(peer_port);*l=sizeof(*p);
    memcpy(b,frame,frame_len);return frame_len;
}
static void reset(void) { locked=0;renew_rc=0;renew_calls=0;sends=0;memset(frame,0,sizeof(frame)); }
#define CHECK(x) do { if(!(x)) { printf("FAIL line %d\n",__LINE__);return 1; } } while(0)
int main(void) {
    unsigned char packet[ETH_FRAME_LEN]={0};
    UserName="fixture-user";Password="fixture-password";
    reset();frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==0 && renew_calls==1 && sends==1);
    reset();renew_rc=76;frame[18]=1;frame[21]=5;frame[22]=1;
    CHECK(auth_8021x_Handler(frame)==76 && renew_calls==1 && sends==0);
    reset();renew_rc=75;frame[18]=1;frame[21]=22;frame[22]=4;frame[23]=16;
    CHECK(auth_8021x_Handler(frame)==76 && renew_calls==1 && sends==0);
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
    puts("ALL 14 PROTOCOL CHECKS PASSED (no network operations)");
    return 0;
}
