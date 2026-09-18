#!/usr/bin/env python3
"""
Quickshell Native Wi-Fi Controller
Provides full standalone NetworkManager Wi-Fi management
(status JSON, toggle, rescan, connect, connect with password, disconnect, forget)
designed for sub-100ms queries and clean DE integration.
"""

import sys
import subprocess
import json
import re
import os
import time

SCAN_FLAG_FILE = "/tmp/qs_wifi_scan.flag"

def get_wifi_interface():
    try:
        out = subprocess.run(
            ['nmcli', '-t', '-f', 'DEVICE,TYPE', 'device'],
            capture_output=True, text=True, timeout=2
        ).stdout
        for line in out.splitlines():
            parts = line.strip().split(':')
            if len(parts) >= 2 and parts[1] == 'wifi':
                return parts[0]
    except Exception:
        pass
    return 'wlan0'

def get_rfkill_blocked():
    try:
        res = subprocess.run(['rfkill', 'list', 'wifi'], capture_output=True, text=True, timeout=2)
        return 'Soft blocked: yes' in res.stdout or 'Hard blocked: yes' in res.stdout
    except Exception:
        return False

def is_scanning():
    if os.path.exists(SCAN_FLAG_FILE):
        try:
            mtime = os.path.getmtime(SCAN_FLAG_FILE)
            if time.time() - mtime < 12:
                return True
            else:
                os.remove(SCAN_FLAG_FILE)
        except Exception:
            pass
    return False

def get_status():
    iface = get_wifi_interface()
    rf_blocked = get_rfkill_blocked()
    
    # 1. Radio status
    radio_out = ""
    try:
        radio_out = subprocess.run(['nmcli', 'radio', 'wifi'], capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        pass
    enabled = (radio_out == 'enabled') and not rf_blocked
    
    scanning = is_scanning()
    
    status = {
        'enabled': enabled,
        'interface': iface,
        'scanning': scanning,
        'connected': False,
        'active': None,
        'known_networks': [],
        'other_networks': [],
        'all_networks': [],
        'saved_profiles': []
    }
    
    if not enabled:
        return status

    # 2. Saved connections
    saved_names = set()
    try:
        saved_out = subprocess.run(
            ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show'],
            capture_output=True, text=True, timeout=2
        ).stdout
        for line in saved_out.splitlines():
            parts = line.strip().split(':')
            if len(parts) >= 2 and parts[1] == '802-11-wireless':
                saved_names.add(parts[0])
    except Exception:
        pass
    status['saved_profiles'] = list(saved_names)

    # 3. Active connection details from device
    active_ssid = ''
    ip_address = ''
    gateway = ''
    dns_servers = []
    try:
        dev_out = subprocess.run(
            ['nmcli', '-t', '-f', 'GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS', 'device', 'show', iface],
            capture_output=True, text=True, timeout=2
        ).stdout
        for line in dev_out.splitlines():
            if line.startswith('GENERAL.CONNECTION:'):
                conn_name = line.split(':', 1)[1].strip()
                if conn_name and conn_name != '--':
                    active_ssid = conn_name
            elif line.startswith('IP4.ADDRESS'):
                val = line.split(':', 1)[1].strip()
                if not ip_address:
                    ip_address = val
            elif line.startswith('IP4.GATEWAY:'):
                val = line.split(':', 1)[1].strip()
                if val and val != '--':
                    gateway = val
            elif line.startswith('IP4.DNS'):
                val = line.split(':', 1)[1].strip()
                if val and val not in dns_servers:
                    dns_servers.append(val)
    except Exception:
        pass

    # 4. Scanned APs
    networks_by_ssid = {}
    active_network_obj = None

    try:
        wifi_out = subprocess.run(
            ['nmcli', '-t', '-e', 'yes', '-f', 'IN-USE,BSSID,SSID,MODE,CHAN,FREQ,RATE,SIGNAL,BARS,SECURITY', 'device', 'wifi', 'list', '--rescan', 'no'],
            capture_output=True, text=True, timeout=3
        ).stdout
        
        for line in wifi_out.splitlines():
            if not line.strip():
                continue
            # nmcli escapes colons with '\:'
            escaped_line = line.replace(r'\:', '___COLON___')
            parts = [p.replace('___COLON___', ':') for p in escaped_line.split(':')]
            if len(parts) < 10:
                continue
                
            in_use = (parts[0].strip() == '*')
            bssid = parts[1].strip()
            ssid = parts[2].strip()
            mode = parts[3].strip()
            chan = parts[4].strip()
            freq = parts[5].strip()
            rate = parts[6].strip()
            try:
                signal = int(parts[7].strip())
            except ValueError:
                signal = 0
            bars = parts[8].strip()
            sec_raw = parts[9].strip()
            
            if not ssid:
                continue
                
            # Clean frequency / band
            band = '2.4 GHz'
            try:
                freq_num = int(re.sub(r'[^\d]', '', freq))
                if freq_num >= 5925:
                    band = '6 GHz'
                elif freq_num >= 4900:
                    band = '5 GHz'
            except Exception:
                pass

            # Classify security
            is_locked = bool(sec_raw and sec_raw != '--' and 'none' not in sec_raw.lower())
            clean_sec = 'Open'
            if 'WPA3' in sec_raw:
                clean_sec = 'WPA3'
            elif 'WPA2' in sec_raw and 'WPA1' in sec_raw:
                clean_sec = 'WPA/WPA2'
            elif 'WPA2' in sec_raw:
                clean_sec = 'WPA2'
            elif 'WPA' in sec_raw:
                clean_sec = 'WPA'
            elif 'WEP' in sec_raw:
                clean_sec = 'WEP'

            is_saved = (ssid in saved_names)
            is_active = in_use or (ssid == active_ssid and bool(active_ssid))
            
            # Map signal to Nerd Font icon
            if signal >= 75:
                icon = '󰤨' if not is_locked else '󰤩'
            elif signal >= 50:
                icon = '󰤥' if not is_locked else '󰤦'
            elif signal >= 25:
                icon = '󰤢' if not is_locked else '󰤣'
            else:
                icon = '󰤟' if not is_locked else '󰤠'

            net_data = {
                'ssid': ssid,
                'bssid': bssid,
                'signal': signal,
                'bars': bars or '▂▄▆█',
                'icon': icon,
                'security': clean_sec,
                'raw_security': sec_raw,
                'is_locked': is_locked,
                'band': band,
                'chan': chan,
                'rate': rate,
                'active': is_active,
                'saved': is_saved
            }
            
            if is_active:
                status['connected'] = True
                active_network_obj = dict(net_data)
                active_network_obj.update({
                    'ip': ip_address or 'Acquiring...',
                    'gateway': gateway or '--',
                    'dns': ', '.join(dns_servers) if dns_servers else '--'
                })
            
            # Keep strongest signal per SSID
            if ssid not in networks_by_ssid or signal > networks_by_ssid[ssid]['signal']:
                networks_by_ssid[ssid] = net_data

    except Exception:
        pass

    # If active network was not in wifi list (e.g. hidden SSID or scan delay)
    if active_ssid and not active_network_obj:
        status['connected'] = True
        active_network_obj = {
            'ssid': active_ssid,
            'bssid': '--',
            'signal': 70,
            'bars': '▂▄▆_',
            'icon': '󰤥',
            'security': 'Secured',
            'raw_security': '',
            'is_locked': True,
            'band': '--',
            'chan': '--',
            'rate': '--',
            'active': True,
            'saved': True,
            'ip': ip_address or 'Connected',
            'gateway': gateway or '--',
            'dns': ', '.join(dns_servers) if dns_servers else '--'
        }

    status['active'] = active_network_obj
    
    # Separate into Known Networks and Other Networks
    known = []
    other = []
    
    for ssid, net in sorted(networks_by_ssid.items(), key=lambda x: x[1]['signal'], reverse=True):
        if net.get('active'):
            continue  # active is shown in primary hero card
        if net.get('saved'):
            known.append(net)
        else:
            other.append(net)
            
    status['known_networks'] = known
    status['other_networks'] = other
    status['all_networks'] = list(networks_by_ssid.values())
    
    return status

def power_on():
    subprocess.run(['nmcli', 'radio', 'wifi', 'on'], capture_output=True, timeout=5)

def power_off():
    subprocess.run(['nmcli', 'radio', 'wifi', 'off'], capture_output=True, timeout=5)

def toggle():
    st = get_status()
    if st.get('enabled', False):
        power_off()
    else:
        power_on()

def rescan():
    try:
        with open(SCAN_FLAG_FILE, 'w') as f:
            f.write(str(os.getpid()))
    except Exception:
        pass
    try:
        # Run nmcli rescan
        subprocess.run(['nmcli', 'device', 'wifi', 'rescan'], capture_output=True, timeout=8)
    except Exception:
        pass
    finally:
        try:
            if os.path.exists(SCAN_FLAG_FILE):
                os.remove(SCAN_FLAG_FILE)
        except Exception:
            pass

def get_saved_connections_with_uuids():
    try:
        out = subprocess.run(['nmcli', '-t', '-f', 'UUID,NAME,TYPE', 'connection', 'show'], 
                             capture_output=True, text=True, timeout=5).stdout
        conns = {}
        for line in out.splitlines():
            parts = line.strip().split(':')
            if len(parts) >= 3 and ('802-11-wireless' in parts[2] or 'wifi' in parts[2]):
                conns[parts[0]] = parts[1]
        return conns
    except Exception:
        return {}

def cleanup_failed_connection(ssid, was_saved, before_conns):
    """Clean up any connection profiles created during a failed connection attempt."""
    try:
        after_conns = get_saved_connections_with_uuids()
        new_uuids = set(after_conns.keys()) - set(before_conns.keys())
        for u in new_uuids:
            subprocess.run(['nmcli', 'connection', 'delete', 'uuid', u], capture_output=True, timeout=5)
        if not was_saved:
            subprocess.run(['nmcli', 'connection', 'delete', 'id', ssid], capture_output=True, timeout=5)
    except Exception:
        pass

def connect(ssid, password=None, hidden=False):
    iface = get_wifi_interface()
    before_conns = get_saved_connections_with_uuids()
    was_saved = any(name == ssid for name in before_conns.values())

    cmd = []
    if was_saved and not password:
        cmd = ['nmcli', 'connection', 'up', 'id', ssid]
    else:
        cmd = ['nmcli', 'device', 'wifi', 'connect', ssid]
        if password:
            cmd.extend(['password', password])
        if hidden:
            cmd.extend(['hidden', 'yes'])

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
        if res.returncode == 0:
            return {'success': True, 'error': None, 'ssid': ssid}
        else:
            cleanup_failed_connection(ssid, was_saved, before_conns)
            err = res.stderr.strip() or res.stdout.strip()
            if 'Secrets were required' in err or 'property is invalid' in err or 'No agents were available' in err:
                err_msg = 'Incorrect password. Please try again.'
            elif 'Timeout' in err:
                err_msg = 'Connection timed out. Check signal and try again.'
            elif 'No network with SSID' in err:
                err_msg = 'Network not found or out of range.'
            else:
                err_msg = err or 'Failed to connect to network.'
            return {'success': False, 'error': err_msg, 'ssid': ssid}
    except subprocess.TimeoutExpired:
        cleanup_failed_connection(ssid, was_saved, before_conns)
        return {'success': False, 'error': 'Connection timed out after 25 seconds.', 'ssid': ssid}
    except Exception as e:
        cleanup_failed_connection(ssid, was_saved, before_conns)
        return {'success': False, 'error': str(e), 'ssid': ssid}

def disconnect():
    iface = get_wifi_interface()
    try:
        res = subprocess.run(['nmcli', 'device', 'disconnect', iface], capture_output=True, text=True, timeout=6)
        return {'success': res.returncode == 0}
    except Exception as e:
        return {'success': False, 'error': str(e)}

def forget(ssid):
    try:
        res = subprocess.run(['nmcli', 'connection', 'delete', 'id', ssid], capture_output=True, text=True, timeout=6)
        return {'success': res.returncode == 0}
    except Exception as e:
        return {'success': False, 'error': str(e)}

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    arg1 = sys.argv[2] if len(sys.argv) > 2 else ''
    arg2 = sys.argv[3] if len(sys.argv) > 3 else ''

    if action in ('status', 'json'):
        print(json.dumps(get_status()))
    elif action == 'toggle':
        toggle()
        print(json.dumps(get_status()))
    elif action == 'on':
        power_on()
        print(json.dumps(get_status()))
    elif action == 'off':
        power_off()
        print(json.dumps(get_status()))
    elif action == 'rescan':
        rescan()
        print(json.dumps(get_status()))
    elif action == 'connect':
        # connect <ssid> [password]
        res = connect(arg1, arg2 if arg2 else None)
        print(json.dumps(res))
    elif action == 'connect-hidden':
        # connect-hidden <ssid> [password]
        res = connect(arg1, arg2 if arg2 else None, hidden=True)
        print(json.dumps(res))
    elif action == 'disconnect':
        res = disconnect()
        print(json.dumps(res))
    elif action == 'forget':
        res = forget(arg1)
        print(json.dumps(res))
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
