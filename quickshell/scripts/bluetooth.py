#!/usr/bin/env python3
"""
Quickshell Native Bluetooth Controller
Provides full standalone BlueZ management (status JSON, toggle, scan, pair, connect, disconnect, remove, discoverable)
without depending on external settings applications.
Uses native D-Bus for sub-3ms queries and zero-latency state changes.
"""

import sys
import subprocess
import json
import re
import time
import os
import signal
import dbus

SCAN_PID_FILE = "/tmp/qs_bt_scan.pid"

def get_rfkill_blocked():
    try:
        res = subprocess.run(["rfkill", "list", "bluetooth"], capture_output=True, text=True, timeout=1)
        return "Soft blocked: yes" in res.stdout or "Hard blocked: yes" in res.stdout
    except Exception:
        return False

def classify_icon(raw_icon, name):
    raw = (raw_icon + " " + name).lower()
    if any(k in raw for k in ["headphone", "headset", "airpod", "buds", "earphone", "audio-card", "pro’s", "pros"]):
        return "headphones"
    if any(k in raw for k in ["speaker", "soundbar", "audio-speaker"]):
        return "speaker"
    if any(k in raw for k in ["mouse", "trackpad", "touchpad"]):
        return "mouse"
    if any(k in raw for k in ["keyboard", "keypad"]):
        return "keyboard"
    if any(k in raw for k in ["gamepad", "controller", "joystick", "xbox", "playstation", "dualsense", "dualshock"]):
        return "controller"
    if any(k in raw for k in ["phone", "iphone", "android", "galaxy", "pixel"]):
        return "phone"
    if any(k in raw for k in ["computer", "laptop", "pc", "macbook"]):
        return "laptop"
    if any(k in raw for k in ["tv", "display", "monitor", "stb"]):
        return "tv"
    if any(k in raw for k in ["watch", "wearable", "band"]):
        return "watch"
    return "bluetooth"

def get_status():
    rf_blocked = get_rfkill_blocked()
    try:
        bus = dbus.SystemBus()
        manager = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
        objects = manager.GetManagedObjects()
    except Exception:
        objects = {}

    adapter_props = {}
    paired = []
    available = []

    for path, ifaces in objects.items():
        if "org.bluez.Adapter1" in ifaces:
            adapter_props = ifaces["org.bluez.Adapter1"]
            break

    powered = bool(adapter_props.get("Powered", False)) and not rf_blocked
    discovering = bool(adapter_props.get("Discovering", False))
    discoverable = bool(adapter_props.get("Discoverable", False))
    name = str(adapter_props.get("Alias", adapter_props.get("Name", "HP-Cachy")))

    if powered:
        for path, ifaces in objects.items():
            if "org.bluez.Device1" in ifaces:
                d = ifaces["org.bluez.Device1"]
                mac = str(d.get("Address", ""))
                dev_name = str(d.get("Name", d.get("Alias", mac)))
                connected = bool(d.get("Connected", False))
                is_paired = bool(d.get("Paired", False))
                trusted = bool(d.get("Trusted", False))
                raw_icon = str(d.get("Icon", ""))

                battery = None
                if "org.bluez.Battery1" in ifaces:
                    try:
                        battery = int(ifaces["org.bluez.Battery1"].get("Percentage", 0))
                    except Exception:
                        battery = None

                info = {
                    "mac": mac,
                    "name": dev_name,
                    "icon": classify_icon(raw_icon, dev_name),
                    "connected": connected,
                    "trusted": trusted,
                    "battery": battery
                }

                if is_paired:
                    paired.append(info)
                else:
                    clean = dev_name.replace("-", ":").replace("_", ":").lower()
                    if clean != mac.lower() and len(dev_name.strip()) > 0:
                        available.append({
                            "mac": mac,
                            "name": dev_name,
                            "icon": classify_icon(raw_icon, dev_name)
                        })

    paired.sort(key=lambda x: (not x["connected"], x["name"].lower()))
    available.sort(key=lambda x: x["name"].lower())

    return {
        "enabled": powered,
        "discovering": discovering,
        "discoverable": discoverable,
        "name": name,
        "paired": paired,
        "available": available
    }

def power_on():
    if get_rfkill_blocked():
        subprocess.run(["rfkill", "unblock", "bluetooth"], capture_output=True)
        time.sleep(0.2)
    try:
        bus = dbus.SystemBus()
        props = dbus.Interface(bus.get_object("org.bluez", "/org/bluez/hci0"), "org.freedesktop.DBus.Properties")
        props.Set("org.bluez.Adapter1", "Powered", True)
        return True
    except Exception:
        for _ in range(5):
            res = subprocess.run(["bluetoothctl", "power", "on"], capture_output=True, text=True)
            if res.returncode == 0:
                return True
            time.sleep(0.2)
    return False

def power_off():
    scan_stop()
    try:
        bus = dbus.SystemBus()
        props = dbus.Interface(bus.get_object("org.bluez", "/org/bluez/hci0"), "org.freedesktop.DBus.Properties")
        props.Set("org.bluez.Adapter1", "Powered", False)
        return True
    except Exception:
        subprocess.run(["bluetoothctl", "power", "off"], capture_output=True)
    return True

def toggle():
    status = get_status()
    if status.get("enabled", False):
        power_off()
    else:
        power_on()

def scan_start(timeout=30):
    scan_stop()
    proc = subprocess.Popen(
        ["bluetoothctl", "--timeout", str(timeout), "scan", "on"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        with open(SCAN_PID_FILE, "w") as f:
            f.write(str(proc.pid))
    except Exception:
        pass

def scan_stop():
    if os.path.exists(SCAN_PID_FILE):
        try:
            with open(SCAN_PID_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
        try:
            os.remove(SCAN_PID_FILE)
        except Exception:
            pass

def scan_toggle():
    status = get_status()
    if status.get("discovering", False):
        scan_stop()
    else:
        scan_start()

def discoverable_toggle():
    try:
        bus = dbus.SystemBus()
        props = dbus.Interface(bus.get_object("org.bluez", "/org/bluez/hci0"), "org.freedesktop.DBus.Properties")
        cur = bool(props.Get("org.bluez.Adapter1", "Discoverable"))
        props.Set("org.bluez.Adapter1", "Discoverable", not cur)
    except Exception:
        subprocess.run(["bluetoothctl", "discoverable", "on"], capture_output=True)

def connect(mac):
    try:
        subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, timeout=8)
    except Exception:
        pass

def disconnect(mac):
    try:
        subprocess.run(["bluetoothctl", "disconnect", mac], capture_output=True, timeout=5)
    except Exception:
        pass

def pair(mac):
    try:
        subprocess.run(["bluetoothctl", "pair", mac], capture_output=True, timeout=12)
        subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, timeout=4)
        subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, timeout=8)
    except Exception:
        pass

def remove(mac):
    try:
        subprocess.run(["bluetoothctl", "untrust", mac], capture_output=True, timeout=3)
        subprocess.run(["bluetoothctl", "remove", mac], capture_output=True, timeout=5)
    except Exception:
        pass

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""

    if action in ("status", "json"):
        print(json.dumps(get_status()))
    elif action == "toggle":
        toggle()
        print(json.dumps(get_status()))
    elif action == "on":
        power_on()
        print(json.dumps(get_status()))
    elif action == "off":
        power_off()
        print(json.dumps(get_status()))
    elif action in ("scan", "scan-toggle"):
        scan_toggle()
        print(json.dumps(get_status()))
    elif action in ("scan-start", "scan-on"):
        scan_start()
        print(json.dumps(get_status()))
    elif action in ("scan-stop", "scan-off"):
        scan_stop()
        print(json.dumps(get_status()))
    elif action in ("discoverable", "discoverable-toggle"):
        discoverable_toggle()
        print(json.dumps(get_status()))
    elif action == "connect" and arg:
        connect(arg)
        print(json.dumps(get_status()))
    elif action == "disconnect" and arg:
        disconnect(arg)
        print(json.dumps(get_status()))
    elif action == "pair" and arg:
        pair(arg)
        print(json.dumps(get_status()))
    elif action == "remove" and arg:
        remove(arg)
        print(json.dumps(get_status()))
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
