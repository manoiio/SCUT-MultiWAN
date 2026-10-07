/* No credentials: release through the same multicast/broadcast paths
 * used by discovery. Silence never confirms release. Drain unrelated frames
 * within a monotonic bound instead of consuming one frame per send. */
int auth_8021x_Logoff(void) {
    uint8_t packet[ETH_FRAME_LEN] = {0};
    int confirmed=0;
    for (int attempt=0; attempt<2; attempt++) {
        uint8_t *header=attempt ? BroadcastHeader : MultcastHeader;
        int length=AppendDrcomLogoffPkt(header,send_8021x_data);
        if (auth_8021x_Sender(send_8021x_data,length)!=1) return -1;
        time_t until=wired_now()+2;
        for (int reads=0; reads<64 && wired_now()<until; reads++) {
            fd_set ready;
            FD_ZERO(&ready); FD_SET(auth_8021x_sock,&ready);
            struct timeval wait={0,250000};
            int rc=select(auth_8021x_sock+1,&ready,NULL,NULL,&wait);
            if (rc<0) { if (errno==EINTR) continue; return -1; }
            if (rc && auth_8021x_Receiver(packet) && packet[15]==0 &&
                packet[18]==FAILURE) confirmed=1;
            if (confirmed) break;
        }
        if (confirmed) break;
    }
    if (!confirmed && !resev && wired_locked() && !wired_stopping()) {
        /* After a power loss the switch may no longer answer unsolicited
         * Logoff. Discover only: never invoke the Identity/MD5 handler. */
        uint8_t peer[14]={0};
        int found=0;
        int length=appendStartPkt(BroadcastHeader);
        if (auth_8021x_Sender(send_8021x_data,length)!=1) return -1;
        time_t until=wired_now()+3;
        for (int reads=0; reads<64 && wired_now()<until; reads++) {
            fd_set ready; FD_ZERO(&ready); FD_SET(auth_8021x_sock,&ready);
            struct timeval wait={0,250000};
            int rc=select(auth_8021x_sock+1,&ready,NULL,NULL,&wait);
            if (rc<0) { if(errno==EINTR) continue; return -1; }
            if (!rc || !auth_8021x_Receiver(packet) || packet[15]!=0) continue;
            if (!found && packet[18]==1 && packet[22]==1 && !(packet[6]&1)) {
                memcpy(peer,packet+6,6); memcpy(peer+6,MAC,6);
                peer[12]=0x88;peer[13]=0x8e;
                length=AppendDrcomLogoffPkt(peer,send_8021x_data);
                if(auth_8021x_Sender(send_8021x_data,length)!=1) return -1;
                found=1;
            } else if(found && packet[18]==FAILURE && !memcmp(peer,packet+6,6)) {
                confirmed=1;break;
            }
        }
        syslog(LOG_INFO,"phase=release-discovery peer-found=%d confirmed=%d",found,confirmed);
    }
    syslog(LOG_INFO,"phase=logoff confirmed=%d",confirmed);
    return confirmed;
}
