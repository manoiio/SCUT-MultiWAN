# School type=1 is local to the request source; never use it for another IP.
reset
run_rc 0 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
grep -q '^REMOTE_UNBIND phy3-sta0 167837962 type=2 mac=001122334410' "$TEST_ROOT/trace" || fail 'wrong remote target/type/MAC'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = 'none none' ] || fail 'verified target retained'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/usb.session")" = '10.2.2.20 phy3-sta0' ] || fail 'peer journal changed'
[ ! -e "$TEST_ROOT/phy3-sta0-offline" ] || fail 'peer logged out'
pass 'remote Native release selects the exact IP and hardware MAC with type 2 and preserves USB'
reset
TEST_NO_ADDRESS=phy0-sta0; export TEST_NO_ADDRESS
run_rc 0 "$BIN/campus-portal-logout" phy0-sta0 10.1.1.10
grep -q '^REMOTE_UNBIND phy3-sta0 ' "$TEST_ROOT/trace" || fail 'missing source did not use protected peer'
! grep -q '^LOGOUT phy0-sta0 ' "$TEST_ROOT/trace" || fail 'addressless interface issued local logout'
pass 'an addressless old interface never sends a source-local unbind'
for flag in TEST_REMOTE_FIND_FAIL TEST_REMOTE_BAD_MAC; do
 reset
 export "$flag=1"
 run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
 ! grep -q '^LOGOUT' "$TEST_ROOT/trace" || fail 'unverified lookup mutated sessions'
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = '10.1.1.10 phy0-sta0' ] || fail 'lookup error erased journal'
done
pass 'incomplete lookup and invalid MAC cannot authorize any release'
reset
printf '{"result":1,"list":[{"online_ip":"10.2.2.20","online_mac":"001122334420"},{"online_ip":"10.1.1.10"}]}' > "$TEST_ROOT/incomplete-list.json"
TEST_REMOTE_FIND_BODY="$TEST_ROOT/incomplete-list.json"; export TEST_REMOTE_FIND_BODY
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
! grep -q '^LOGOUT' "$TEST_ROOT/trace" || fail 'missing target MAC treated as absence'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" != 'none none' ] || fail 'incomplete row cleared journal'
pass 'a present target row without a MAC fails closed instead of being called absent'
reset
TEST_REMOTE_KEEP_TARGET=1; export TEST_REMOTE_KEEP_TARGET
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" != 'none none' ] || fail 'bare success cleared journal'
pass 'result=1 cannot release a journal while the exact target remains listed'
reset
TEST_REMOTE_UNBIND_TIMEOUT=1; export TEST_REMOTE_UNBIND_TIMEOUT
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" != 'none none' ] || fail 'uncertain mutation erased journal'
pass 'a remote mutation timeout retains the occupied-slot journal'
reset
touch "$TEST_ROOT/remote-released-10.1.1.10"
MW_MANUAL_LOGIN=1 run_rc 0 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
! grep -q '^LOGOUT' "$TEST_ROOT/trace" || fail 'confirmed absent target was mutated'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" = 'none none' ] || fail 'explicit confirmed absence not reconciled'
pass 'manual admission reconciles a twice-absent target with positive peer controls and no mutation'
reset
touch "$TEST_ROOT/remote-released-10.1.1.10"
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.login-paused")" = vanished ] || fail 'automatic absence was not paused'
[ "$(cat "$TEST_ROOT/etc/scut-multiwan/native.session")" != 'none none' ] || fail 'automatic absence cleared journal'
pass 'automatic remote absence pauses login and retains the session record'
reset
printf '\nUSB_USER=other-user\n' >> "$TEST_ROOT/etc/campus-portal.conf"
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
! grep -q '^REMOTE_FIND\|^LOGOUT' "$TEST_ROOT/trace" || fail 'different account queried or released peer'
pass 'a peer using another account cannot provide remote ownership confirmation'
reset
touch "$TEST_ROOT/changed-ip-phy3-sta0"
run_rc 75 "$BIN/campus-portal-logout" phy3-sta0 10.1.1.10
! grep -q '^LOGOUT' "$TEST_ROOT/trace" || fail 'changed source mutated session'
pass 'changed source identity blocks remote release before mutation'
