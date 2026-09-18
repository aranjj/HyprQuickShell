#!/usr/bin/env python3
import sys
import json
import subprocess
import re
from pathlib import Path

def get_monitors():
    try:
        raw = subprocess.check_output(['hyprctl', '-i', '0', '-j', 'monitors', 'all'], text=True)
    except Exception:
        try:
            raw = subprocess.check_output(['hyprctl', '-j', 'monitors', 'all'], text=True)
        except Exception:
            raw = '[]'
    try:
        monitors = json.loads(raw)
    except Exception:
        monitors = []

    res = []
    for m in monitors:
        res.append({
            'id': m.get('id', 0),
            'name': m.get('name', 'Unknown'),
            'description': m.get('description', ''),
            'make': m.get('make', ''),
            'model': m.get('model', ''),
            'width': m.get('width', 1920),
            'height': m.get('height', 1080),
            'refreshRate': round(float(m.get('refreshRate', 60.0)), 1),
            'scale': round(float(m.get('scale', 1.0)), 2),
            'transform': int(m.get('transform', 0)),
            'focused': bool(m.get('focused', False)),
            'dpmsStatus': bool(m.get('dpmsStatus', True)),
            'vrr': bool(m.get('vrr', False)),
            'availableModes': m.get('availableModes', [])
        })
    return res

def apply_monitor(name, mode="preferred", pos="auto", scale=1.0, transform=0, vrr=0):
    try:
        scale_val = round(float(scale), 2)
        scale_str = f"{scale_val:.2f}".rstrip('0').rstrip('.')
        if scale_str == "":
            scale_str = "1"
    except Exception:
        scale_str = "1"

    # 1. Apply dynamically via Hyprland Lua parser eval
    lua_code = (
        f'hl.monitor({{ '
        f'output = "{name}", '
        f'mode = "{mode}", '
        f'position = "{pos}", '
        f'scale = "{scale_str}", '
        f'transform = {int(transform)}, '
        f'vrr = {int(vrr)} '
        f'}})'
    )
    res = subprocess.run(['hyprctl', 'eval', lua_code], capture_output=True, text=True)
    
    # Fallback to standard hyprctl keyword if eval failed
    if res.returncode != 0 or 'error:' in res.stdout:
        kw_cmd = f'{name},{mode},{pos},{scale_str},transform,{int(transform)}'
        subprocess.run(['hyprctl', 'keyword', 'monitor', kw_cmd], capture_output=True, text=True)

    # 2. Persist to hyprland.lua in both ~/.config/hypr and ~/dotfiles/hypr
    persist_paths = [
        Path.home() / '.config/hypr/hyprland.lua',
        Path.home() / 'dotfiles/hypr/hyprland.lua'
    ]
    for p in persist_paths:
        if p.exists():
            try:
                content = p.read_text()
                # Pattern for scale = "..."
                pattern = r'(scale\s*=\s*")[^"]*(")'
                new_content = re.sub(pattern, rf'\g<1>{scale_str}\g<2>', content)
                if new_content != content:
                    p.write_text(new_content)
            except Exception:
                pass

    return {'success': True, 'name': name, 'scale': scale_str, 'mode': mode}

def set_dpms(name, state="toggle"):
    subprocess.run(['hyprctl', 'dispatch', 'dpms', state, name], capture_output=True, text=True)
    return {'success': True, 'name': name, 'state': state}

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'list':
        print(json.dumps(get_monitors()))
    elif len(sys.argv) > 1 and sys.argv[1] == 'apply':
        # args: apply <name> <mode> <pos> <scale> [transform] [vrr]
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        mode = sys.argv[3] if len(sys.argv) > 3 else "preferred"
        pos = sys.argv[4] if len(sys.argv) > 4 else "auto"
        scale = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
        transform = int(sys.argv[6]) if len(sys.argv) > 6 else 0
        vrr = int(sys.argv[7]) if len(sys.argv) > 7 else 0
        print(json.dumps(apply_monitor(name, mode, pos, scale, transform, vrr)))
    elif len(sys.argv) > 1 and sys.argv[1] == 'dpms':
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        state = sys.argv[3] if len(sys.argv) > 3 else "toggle"
        print(json.dumps(set_dpms(name, state)))
    else:
        print(json.dumps(get_monitors()))
