/* AGPL-3.0-or-later. Event-loop lock contention, never a new Start. */
static uint8_t pending_challenge[ETH_FRAME_LEN];
static int pending_valid;
static time_t pending_since;
int wired_pending_poll(void) {
    if (!pending_valid) return 0;
    if (wired_stopping() || wired_now() - pending_since >= 15) return 76;
    int rc = wired_renew();
    if (rc == 75) return 0;
    if (rc) return 76;
    pending_valid = 0;
    return auth_8021x_Handler(pending_challenge);
}
int wired_challenge_admit(const uint8_t *frame) {
    if (wired_locked()) return 0;
    int rc = wired_renew();
    if (rc != 75) return rc ? 76 : 0;
    unsigned int len = ((unsigned int)frame[20] << 8) | frame[21];
    if (len < 5 || len > ETH_FRAME_LEN - 18) return 76;
    if (!pending_valid) pending_since = wired_now();
    memcpy(pending_challenge, frame, len + 18);
    pending_valid = 1;
    return 77; /* Accepted for later processing; no response without the lock. */
}
