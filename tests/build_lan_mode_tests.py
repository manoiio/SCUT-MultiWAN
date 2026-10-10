#!/usr/bin/env python3
"""Generate an isolated BusyBox/Linux LAN controller suite; never run on macOS."""
import argparse
import io
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
REMOTE = "/tmp/scut-lan-tests-v2"


def build(output: Path) -> None:
    controller = (ROOT / "candidate/usr/bin/scut-lan-mode").read_text()
    controller = controller.replace("CFG=/etc/scut-lan/mode", f"CFG={REMOTE}/cfg/mode")
    controller = controller.replace("RUN=/var/run/scut-lan", f"RUN={REMOTE}/run")
    for service in ("dns", "tunnel"):
        controller = controller.replace(f"/etc/init.d/scut-lan-{service}", f"{REMOTE}/bin/service")
    controller = controller.replace("logger -t scut-lan", ":")
    files = {
        "controller": controller,
        "run.sh": (ROOT / "tests/lan-mode-cases.sh").read_text(),
        "bin/ip": f'''#!/bin/sh
printf '%s\\n' "$*" >> {REMOTE}/ip.log
case "$*" in
 '-4 route show table 103') [ ! -f {REMOTE}/healthy ] || echo 'default via 110.64.88.254 dev wan';;
 '-6 route show default dev wan') echo 'default via fe80::1 dev wan';;
 *'route del '*) exit 2;;
esac
''',
        "bin/nft": f'''#!/bin/sh
printf '%s\\n' "$*" >> {REMOTE}/nft.log
case "$*" in *' -') cat >> {REMOTE}/nft-input.log;; esac
''',
    }
    for name in ("ubus", "service", "dnsmasq"):
        files[f"bin/{name}"] = "#!/bin/sh\nexit 0\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w") as archive:
        for name, content in files.items():
            data = content.encode()
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            entry.mode = 0o700
            archive.addfile(entry, io.BytesIO(data))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/private/tmp/scut-lan-suite.tar"))
    build(parser.parse_args().output)
