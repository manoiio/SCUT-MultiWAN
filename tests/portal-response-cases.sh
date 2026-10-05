# Fixture-only Portal bodies and fake credentials. Never contact production.
for spec in 'native phy0-sta0 campus-portal' 'usb phy3-sta0 campus-usb'; do
 set -- $spec; slot=$1; dev=$2; entry=$3
 for fixture in portal-small.json portal-boundary.json; do
  reset
  TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0
  TEST_PORTAL_LOGIN_BODY="$TEST_ROOT/fixtures/$fixture"
  export TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_PORTAL_LOGIN_BODY
  run_rc 0 "$BIN/$entry-login" "$dev"
  [ "$(grep -c '^LOGIN ' "$TEST_ROOT/trace")" = 1 ] || fail "$slot normal login count"
  grep -q '^LOGOUT ' "$TEST_ROOT/trace" || fail "$slot release omitted"
  [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" != 'none none' ] || fail "$slot normal login lost journal"
  pass "$slot complete $fixture login retains normal transaction"
  reset
  TEST_PORTAL_LOGOUT_BODY="$TEST_ROOT/fixtures/$fixture"; export TEST_PORTAL_LOGOUT_BODY
  run_rc 0 "$BIN/$entry-logout" "$dev"
  [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" = 'none none' ] || fail "$slot complete logout not cleared"
  pass "$slot complete $fixture logout confirms release"
 done
 for rc in 63 28 18; do
  reset
  TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0
  TEST_PORTAL_LOGIN_BODY="$TEST_ROOT/fixtures/portal-small.json"
  TEST_PORTAL_LOGIN_RC=$rc; TEST_PORTAL_LOG_CAPTURE=1
  export TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_PORTAL_LOGIN_BODY TEST_PORTAL_LOGIN_RC TEST_PORTAL_LOG_CAPTURE
  run_rc 1 "$BIN/$entry-login" "$dev"
  [ "$(grep -c '^LOGIN ' "$TEST_ROOT/trace")" = 1 ] || fail "$slot incomplete response retried"
  [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" != 'none none' ] || fail "$slot incomplete login forgot occupied slot"
  grep -q "curl=$rc; session retained" "$TEST_ROOT/portal-log" || fail "$slot missing safe reason"
  ! grep -q 'PRIVATE_FIXTURE_BODY' "$TEST_ROOT/portal-log" "$TEST_ROOT/last-output" || fail "$slot raw login body logged"
  pass "$slot partial success curl=$rc retains login journal without retry"
  reset
  before=$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")
  TEST_PORTAL_LOGOUT_BODY="$TEST_ROOT/fixtures/portal-small.json"
  TEST_PORTAL_LOGOUT_RC=$rc; TEST_PORTAL_LOG_CAPTURE=1
  export TEST_PORTAL_LOGOUT_BODY TEST_PORTAL_LOGOUT_RC TEST_PORTAL_LOG_CAPTURE
  run_rc 1 "$BIN/$entry-logout" "$dev"
  [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" = "$before" ] || fail "$slot partial logout cleared journal"
  ! grep -q 'PRIVATE_FIXTURE_BODY' "$TEST_ROOT/portal-log" "$TEST_ROOT/last-output" || fail "$slot raw logout body logged"
  pass "$slot partial success curl=$rc cannot confirm release"
 done
 reset
 TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0
 TEST_PORTAL_LOGOUT_BODY="$TEST_ROOT/fixtures/portal-over.json"
 export TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_PORTAL_LOGOUT_BODY
 run_rc 1 "$BIN/$entry-login" "$dev"
 ! grep -q '^LOGIN ' "$TEST_ROOT/trace" || fail "$slot login followed overflowed release"
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" != 'none none' ] || fail "$slot overflowed release deleted journal"
 pass "$slot oversized release containing success prevents subsequent login"
 reset
 TEST_NATIVE_ONLINE=0; TEST_USB_ONLINE=0
 TEST_PORTAL_LOGIN_BODY="$TEST_ROOT/fixtures/portal-over.json"
 export TEST_NATIVE_ONLINE TEST_USB_ONLINE TEST_PORTAL_LOGIN_BODY
 run_rc 1 "$BIN/$entry-login" "$dev"
 [ "$(grep -c '^LOGIN ' "$TEST_ROOT/trace")" = 1 ] || fail "$slot overflowed login repeated"
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" != 'none none' ] || fail "$slot overflowed login journal"
 pass "$slot oversized login preserves uncertain occupied session"
 reset
 TEST_PORTAL_LOGOUT_BODY="$TEST_ROOT/fixtures/portal-failure.json"; export TEST_PORTAL_LOGOUT_BODY
 run_rc 1 "$BIN/$entry-logout" "$dev"
 [ "$(cat "$TEST_ROOT/etc/scut-multiwan/$slot.session")" != 'none none' ] || fail "$slot rejection lost ledger"
 pass "$slot complete rejection preserves existing release behavior"
done
