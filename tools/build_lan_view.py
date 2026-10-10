#!/usr/bin/env python3
"""Give LuCI's custom view a content-specific module URL after source changes."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
base = root / 'candidate/www/luci-static/resources/view/network'
source = (base / 'scut_lan.js').read_bytes()
name = 'scut_lan_' + hashlib.sha256(source).hexdigest()[:12]
(base / (name + '.js')).write_bytes(source)
menu = root / 'candidate/usr/share/luci/menu.d/luci-app-scut-lan.json'
data = json.loads(menu.read_text())
data['admin/network/scut_lan']['action']['path'] = 'network/' + name
menu.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(name)
