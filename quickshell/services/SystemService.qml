pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import "." as Services

Singleton {
    id: root

    // ── User Directory Helper ───────────────────────
    readonly property string homeDir: "/home/aran"

    // ── Popup States ────────────────────────────────
    property bool controlCenterOpen: false
    property bool powerMenuOpen: false

    property string controlCenterTab: "controls"
    property string controlCenterSubView: "main"

    onPowerMenuOpenChanged: {
        if (!powerMenuOpen) {
            Services.OverlayCoordinator.releaseExclusiveSurface("powerMenu");
        }
    }

    function openControlCenter(tab, subview) {
        const targetTab = tab || "controls";
        const targetSub = subview || "main";
        if (controlCenterOpen && controlCenterTab === targetTab && controlCenterSubView === targetSub) {
            controlCenterOpen = false;
            Services.OverlayCoordinator.releaseExclusiveSurface("controlCenter");
        } else {
            controlCenterTab = targetTab;
            controlCenterSubView = targetSub;
            Services.OverlayCoordinator.requestExclusiveSurface("controlCenter");
            controlCenterOpen = true;
            if (targetTab === "controls") {
                if (targetSub === "wifi") rescanWifi();
                else if (targetSub === "bluetooth") {
                    refreshBluetooth();
                    startBluetoothScan();
                } else if (targetSub === "audio") {
                    rescanAudioSinks();
                    rescanAudioSources();
                    rescanAppAudioStreams();
                } else if (targetSub === "battery") {
                    refreshBattery();
                } else if (targetSub === "displays") {
                    rescanMonitors();
                } else {
                    rescanWifi();
                    refreshBluetooth();
                    rescanAudioSinks();
                    rescanAudioSources();
                    rescanAppAudioStreams();
                    rescanMonitors();
                }
            }
        }
    }

    function toggleControlCenter() {
        openControlCenter("controls", "main");
    }

    function togglePowerMenu() {
        powerMenuOpen = !powerMenuOpen;
        if (powerMenuOpen) {
            Services.OverlayCoordinator.requestExclusiveSurface("powerMenu");
        } else {
            Services.OverlayCoordinator.releaseExclusiveSurface("powerMenu");
        }
    }

    property bool aboutDialogOpen: false
    onAboutDialogOpenChanged: {
        if (aboutDialogOpen) {
            Services.OverlayCoordinator.requestExclusiveSurface("aboutDialog");
        } else {
            Services.OverlayCoordinator.releaseExclusiveSurface("aboutDialog");
        }
    }

    Component.onCompleted: {
        Services.OverlayCoordinator.registerExclusiveSurface("controlCenter",
            () => { openControlCenter("controls", "main"); },
            () => { controlCenterOpen = false; }
        );
        Services.OverlayCoordinator.registerExclusiveSurface("powerMenu",
            () => { Services.OverlayCoordinator.requestExclusiveSurface("powerMenu"); powerMenuOpen = true; },
            () => { powerMenuOpen = false; }
        );
        Services.OverlayCoordinator.registerExclusiveSurface("aboutDialog",
            () => { Services.OverlayCoordinator.requestExclusiveSurface("aboutDialog"); aboutDialogOpen = true; },
            () => { aboutDialogOpen = false; }
        );
    }
    property bool caffeineActive: false
    property bool preventLockOnFullscreen: true
    property bool isFullscreenVideoActive: false
    property string fullscreenVideoApp: ""
    property bool isIdleOrLocked: false

    readonly property bool idleInhibited: caffeineActive || (preventLockOnFullscreen && isFullscreenVideoActive)

    function toggleCaffeine() {
        caffeineActive = !caffeineActive;
    }

    Process {
        id: fullscreenCheckProc
        command: ["python3", "-c", "import subprocess, json\ntry:\n    clients = json.loads(subprocess.check_output(['hyprctl', '-i', '0', '-j', 'clients'], text=True))\nexcept:\n    clients = []\nhas_fs = False\nfs_app = ''\nhas_inhibit = False\nfor c in clients:\n    if c.get('inhibitingIdle'):\n        has_inhibit = True\n    if c.get('fullscreen', 0) != 0 or c.get('fullscreenClient', 0) != 0:\n        has_fs = True\n        if not fs_app:\n            fs_app = c.get('class') or c.get('initialClass') or ''\nhas_audio = False\nif has_fs or has_inhibit:\n    try:\n        sinks = json.loads(subprocess.check_output(['pactl', '-f', 'json', 'list', 'sink-inputs'], text=True))\n        for s in sinks:\n            if not s.get('corked', False):\n                has_audio = True\n                break\n    except:\n        pass\nmedia_apps = {'mpv', 'vlc', 'celluloid', 'totem', 'kodi', 'stremio', 'plex', 'jellyfin', 'netflix', 'youtube', 'bilibili'}\nbrowsers = {'firefox', 'chrome', 'chromium', 'brave', 'zen', 'edge', 'google-chrome'}\napp_lower = fs_app.lower()\nis_video = has_inhibit or (has_fs and (has_audio or app_lower in media_apps or app_lower in browsers))\nprint(json.dumps({'active': is_video, 'app': fs_app}))\n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text.trim() || "{}");
                    root.isFullscreenVideoActive = !!res.active;
                    root.fullscreenVideoApp = res.app || "";
                } catch (e) {}
            }
        }
    }

    Timer {
        id: fullscreenPollTimer
        interval: 3000
        running: !root.isIdleOrLocked
        repeat: true
        onTriggered: {
            if (!fullscreenCheckProc.running) fullscreenCheckProc.running = true;
        }
    }

    // ── Displays & Monitor Management ────────────────
    property var monitorsList: []
    property int selectedMonitorIndex: 0
    property var currentMonitor: (monitorsList && monitorsList.length > selectedMonitorIndex) ? monitorsList[selectedMonitorIndex] : (monitorsList && monitorsList.length > 0 ? monitorsList[0] : null)
    property real monitorScale: currentMonitor ? (currentMonitor.scale || 1.0) : 1.0
    property real targetMonitorScale: monitorScale
    property bool isMonitorScalingDragging: false

    onCurrentMonitorChanged: {
        if (currentMonitor && !isMonitorScalingDragging) {
            monitorScale = currentMonitor.scale || 1.0;
            targetMonitorScale = monitorScale;
        }
    }

    Process {
        id: monitorsProc
        command: ["/home/aran/.config/quickshell/scripts/monitors.py", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim() || "[]");
                    root.monitorsList = data;
                    if (root.selectedMonitorIndex >= data.length) {
                        root.selectedMonitorIndex = 0;
                    }
                    if (data.length > 0 && !root.isMonitorScalingDragging) {
                        const m = data[root.selectedMonitorIndex] || data[0];
                        root.monitorScale = m.scale || 1.0;
                        root.targetMonitorScale = root.monitorScale;
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: applyMonitorProc
        command: ["sh", "-c", ""]
        onExited: (code) => {
            monitorsRefreshTimer.restart();
        }
    }

    Timer {
        id: monitorsRefreshTimer
        interval: 350
        repeat: false
        onTriggered: monitorsProc.running = true
    }

    Timer {
        id: monitorScaleDebounceTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (root.currentMonitor) {
                root.applyMonitorScale(root.currentMonitor.name, root.targetMonitorScale);
            }
        }
    }

    function rescanMonitors() {
        monitorsProc.running = true;
    }

    function setTargetScale(val) {
        const clamped = Math.max(0.75, Math.min(2.0, Math.round(val * 20) / 20));
        root.targetMonitorScale = clamped;
        root.monitorScale = clamped;
        monitorScaleDebounceTimer.restart();
    }

    function applyMonitorScale(name, scale) {
        const m = root.currentMonitor;
        const mode = (m && m.width && m.height && m.refreshRate) ? (m.width + "x" + m.height + "@" + Math.round(m.refreshRate)) : "preferred";
        const transform = m ? (m.transform || 0) : 0;
        const vrr = (m && m.vrr) ? 1 : 0;
        applyMonitorProc.command = ["/home/aran/.config/quickshell/scripts/monitors.py", "apply", name, mode, "auto", scale.toFixed(2), transform.toString(), vrr.toString()];
        applyMonitorProc.running = true;
    }

    function applyMonitorMode(name, modeStr) {
        const m = root.currentMonitor;
        const scale = m ? (m.scale || 1.0) : 1.0;
        const transform = m ? (m.transform || 0) : 0;
        const vrr = (m && m.vrr) ? 1 : 0;
        applyMonitorProc.command = ["/home/aran/.config/quickshell/scripts/monitors.py", "apply", name, modeStr, "auto", scale.toFixed(2), transform.toString(), vrr.toString()];
        applyMonitorProc.running = true;
    }

    function setMonitorTransform(name, transformIdx) {
        const m = root.currentMonitor;
        const mode = (m && m.width && m.height && m.refreshRate) ? (m.width + "x" + m.height + "@" + Math.round(m.refreshRate)) : "preferred";
        const scale = m ? (m.scale || 1.0) : 1.0;
        const vrr = (m && m.vrr) ? 1 : 0;
        applyMonitorProc.command = ["/home/aran/.config/quickshell/scripts/monitors.py", "apply", name, mode, "auto", scale.toFixed(2), transformIdx.toString(), vrr.toString()];
        applyMonitorProc.running = true;
    }

    function toggleMonitorDpms(name) {
        applyMonitorProc.command = ["/home/aran/.config/quickshell/scripts/monitors.py", "dpms", name, "toggle"];
        applyMonitorProc.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = (event && event.name) ? event.name : "";
            if (name === "fullscreen" || name === "activewindow" || name === "closewindow") {
                if (!fullscreenCheckProc.running) fullscreenCheckProc.running = true;
            }
            if (name.includes("monitor") || name === "focusedmon") {
                if (!monitorsProc.running) monitorsProc.running = true;
            }
        }
        function onActiveToplevelChanged() {
            if (!fullscreenCheckProc.running) fullscreenCheckProc.running = true;
        }
    }

    function closeAllPopups() {
        controlCenterOpen = false;
        powerMenuOpen = false;
        aboutDialogOpen = false;
        Services.OverlayCoordinator.closeCurrentExclusiveSurface();
    }

    // ── Command Runners ─────────────────────────────
    Process {
        id: execProc
        command: ["sh", "-c", ""]
    }

    function runCmd(cmd) {
        execProc.running = false;
        execProc.command = ["sh", "-c", "cd " + homeDir + " && (" + cmd + ")"];
        execProc.running = true;
    }

    // ── Hyprland Lua User Programs Defaults ──────────
    FileView {
        id: hyprConfigFile
        path: "/home/aran/.config/hypr/hyprland.lua"
        preload: true
        blockLoading: true
    }

    readonly property string defaultTerminal: {
        try {
            const txt = hyprConfigFile.text();
            const m = txt.match(/local\s+terminal\s*=\s*["']([^"']+)["']/);
            if (m && m[1]) return m[1].trim();
        } catch (e) {}
        return "kitty";
    }

    readonly property string defaultFileManager: {
        try {
            const txt = hyprConfigFile.text();
            const m = txt.match(/local\s+fileManager\s*=\s*["']([^"']+)["']/);
            if (m && m[1]) return m[1].trim();
        } catch (e) {}
        return "dolphin";
    }

    readonly property string defaultBrowser: {
        try {
            const txt = hyprConfigFile.text();
            const m = txt.match(/local\s+browser\s*=\s*["']([^"']+)["']/);
            if (m && m[1]) return m[1].trim();
        } catch (e) {}
        return "firefox";
    }

    readonly property string defaultMenu: {
        try {
            const txt = hyprConfigFile.text();
            const m = txt.match(/local\s+menu\s*=\s*["']([^"']+)["']/);
            if (m && m[1]) return m[1].trim();
        } catch (e) {}
        return "hyprlauncher";
    }

    // Run command in user's configured default terminal emulator
    function runInTerminal(cmd, hold) {
        const term = defaultTerminal || "kitty";
        const clean = cmd.replace(/^>/, '').trim();
        if (!clean) return;

        if (term === "kitty") {
            const flag = hold ? "--hold -e " : "-e ";
            runCmd("kitty --directory " + homeDir + " " + flag + clean);
        } else if (term === "alacritty") {
            const flag = hold ? "--hold -e " : "-e ";
            runCmd("alacritty --working-directory " + homeDir + " " + flag + clean);
        } else if (term === "foot") {
            const flag = hold ? "--hold " : "";
            runCmd("foot -D " + homeDir + " " + flag + clean);
        } else if (term === "ghostty") {
            runCmd("ghostty --working-directory=" + homeDir + " -e " + clean);
        } else if (term === "konsole") {
            const flag = hold ? "--hold -e " : "-e ";
            runCmd("konsole --workdir " + homeDir + " " + flag + clean);
        } else {
            if (hold) {
                runCmd(term + " -e sh -c '" + clean.replace(/'/g, "'\\''") + "; printf \"\\n[Process completed. Press Enter to exit]\\n\"; read _'");
            } else {
                runCmd(term + " -e " + clean);
            }
        }
    }

    // Open terminal always in ~/
    function openTerminal() {
        const term = defaultTerminal || "kitty";
        if (term === "kitty") {
            runCmd("kitty --directory " + homeDir);
        } else if (term === "alacritty") {
            runCmd("alacritty --working-directory " + homeDir);
        } else if (term === "foot") {
            runCmd("foot -D " + homeDir);
        } else if (term === "konsole") {
            runCmd("konsole --workdir " + homeDir);
        } else {
            runCmd(term || "kitty");
        }
    }

    // Open btop always in ~/
    function openBtop() {
        runInTerminal("btop", false);
    }

    // Open file manager in ~/
    function openFileManager() {
        runCmd((defaultFileManager || "dolphin") + " " + homeDir);
    }

    // Lock screen (same behavior as Super + L)
    function lockScreen() {
        closeAllPopups();
        runCmd("quickshell ipc call lock lock || loginctl lock-session || hyprlock");
    }

    // ── Distro & Hardware Specs (Auto-detected) ─────
    property string distroId: "cachyos"
    property string distroName: "CachyOS Linux"
    property string distroPrettyName: "CachyOS"
    property string distroIdLike: "arch"
    property string distroGlyph: "󰣇"
    property string hardwareModel: "HP Laptop"
    property string cpuModel: "Intel Core"
    property string ramTotal: "16 GB RAM"
    property string gpuModel: "Intel Graphics"
    property string kernel: "Linux"
    property string kernelShort: ""
    property string compositor: "Hyprland (wayland)"

    function getDistroGlyph(id, idLike) {
        const key = (id || "").toLowerCase().trim();
        const like = (idLike || "").toLowerCase().trim();

        const glyphs = {
            "cachyos": "󰣇",
            "arch": "",
            "fedora": "",
            "ubuntu": "",
            "debian": "",
            "linuxmint": "",
            "mint": "",
            "opensuse": "",
            "opensuse-tumbleweed": "",
            "opensuse-leap": "",
            "suse": "",
            "manjaro": "",
            "nixos": "",
            "gentoo": "",
            "void": "",
            "endeavouros": "",
            "alpine": "",
            "kali": "",
            "pop": "",
            "rhel": "",
            "redhat": "",
            "centos": "",
            "almalinux": "",
            "rocky": "",
            "freebsd": ""
        };

        if (glyphs[key]) return glyphs[key];

        if (like) {
            const parts = like.split(/\s+/);
            for (let i = 0; i < parts.length; i++) {
                if (glyphs[parts[i]]) return glyphs[parts[i]];
            }
        }

        return "";
    }

    Process {
        id: sysInfoProc
        command: ["sh", "-c", "if [ -f /etc/os-release ]; then . /etc/os-release; elif [ -f /usr/lib/os-release ]; then . /usr/lib/os-release; fi; d_id=\"${ID:-linux}\"; d_name=\"${NAME:-Linux}\"; d_pname=\"${PRETTY_NAME:-$d_name}\"; d_like=\"${ID_LIKE:-}\"; kernel=\"$(uname -srm)\"; kernel_short=\"$(uname -r)\"; model=\"$(cat /sys/class/dmi/id/product_name 2>/dev/null || cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || hostname)\"; [ -z \"$model\" ] || [ \"$model\" = \"System Product Name\" ] && model=\"PC / Laptop\"; cpu=\"$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -e 's/^[ \\t]*//' -e 's/(R)//g' -e 's/(TM)//g' -e 's/@.*//')\"; [ -z \"$cpu\" ] && cpu=\"$(uname -m)\"; ram=\"$(awk '/MemTotal/ {printf \"%.0f GB RAM\", $2/1024/1024}' /proc/meminfo 2>/dev/null)\"; gpu=\"$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 | sed -E -e 's/.*: //' -e 's/\\(rev .*\\)//' -e 's/Corporation //' -e 's/Integrated Graphics Controller //' | xargs)\"; [ -z \"$gpu\" ] && gpu=\"Integrated Graphics\"; comp=\"${XDG_CURRENT_DESKTOP:-Wayland} (${XDG_SESSION_TYPE:-wayland})\"; printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s' \"$d_id\" \"$d_name\" \"$d_pname\" \"$d_like\" \"$kernel\" \"$kernel_short\" \"$model\" \"$cpu\" \"$ram\" \"$gpu\" \"$comp\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim().length === 0) return;
                const parts = text.trim().split("\t");
                if (parts.length >= 11) {
                    root.distroId = parts[0] || "linux";
                    root.distroName = parts[1] || "Linux";
                    root.distroPrettyName = parts[2] || root.distroName;
                    root.distroIdLike = parts[3] || "";
                    root.kernel = parts[4] || "Linux";
                    root.kernelShort = parts[5] || "";
                    root.hardwareModel = parts[6] || "PC / Laptop";
                    root.cpuModel = parts[7] || "Unknown CPU";
                    root.ramTotal = parts[8] || "Unknown RAM";
                    root.gpuModel = parts[9] || "Graphics";
                    root.compositor = parts[10] || "Wayland";
                    root.distroGlyph = root.getDistroGlyph(root.distroId, root.distroIdLike);
                }
            }
        }
    }

    // ── CPU ─────────────────────────────────────────
    property string cpuUsage: "0%"
    property real cpuUsageNum: 0
    Process {
        id: cpuProc
        command: ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{printf \"%.0f\", 100 - $1}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim()) || 0;
                root.cpuUsageNum = val;
                root.cpuUsage = val + "%";
            }
        }
    }

    // ── Memory ──────────────────────────────────────
    property string memUsage: "0%"
    property real memUsageNum: 0
    property string memDetail: ""
    Process {
        id: memProc
        command: ["sh", "-c", "free -m | awk 'NR==2{printf \"%.0f %.1f/%.1fGB\", ($3/$2)*100, $3/1024, $2/1024}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                root.memUsageNum = parseInt(parts[0]) || 0;
                root.memUsage = root.memUsageNum + "%";
                root.memDetail = parts[1] || "";
            }
        }
    }

    // ── Temperature ─────────────────────────────────
    property int cpuTemp: 45
    Process {
        id: tempProc
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do if [ -f \"$h/name\" ] && grep -qE 'coretemp|k10temp|cpu' \"$h/name\"; then [ -f \"$h/temp1_input\" ] && awk '{printf \"%.0f\", $1/1000}' \"$h/temp1_input\" && exit 0; fi; done; [ -f /sys/class/thermal/thermal_zone0/temp ] && awk '{printf \"%.0f\", $1/1000}' /sys/class/thermal/thermal_zone0/temp || echo 45"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim()) || 45;
                root.cpuTemp = val;
            }
        }
    }

    // ── Battery & AC Power ──────────────────────────
    property int batteryLevel: 100
    property string batteryIcon: "󰁹"
    property bool batteryCharging: false
    property bool batteryPlugged: false
    property string batteryStatusText: "Full"
    property int batteryHealthPct: 100
    property string batteryCondition: "Normal"
    property int batteryCycles: 0

    Process {
        id: battProc
        command: ["sh", "-c", "printf '%s|%s|%s|%s|%s|%s' \"$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo '100')\" \"$(cat /sys/class/power_supply/BAT*/status 2>/dev/null || echo 'Full')\" \"$(cat /sys/class/power_supply/AD*/online 2>/dev/null || cat /sys/class/power_supply/AC*/online 2>/dev/null || echo '0')\" \"$(cat /sys/class/power_supply/BAT*/cycle_count 2>/dev/null || echo '0')\" \"$(cat /sys/class/power_supply/BAT*/energy_full 2>/dev/null || cat /sys/class/power_supply/BAT*/charge_full 2>/dev/null || echo '0')\" \"$(cat /sys/class/power_supply/BAT*/energy_full_design 2>/dev/null || cat /sys/class/power_supply/BAT*/charge_full_design 2>/dev/null || echo '0')\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                const level = parseInt(parts[0]) || 100;
                const status = (parts[1] || "Full").trim();
                const acOnline = parseInt(parts[2]) === 1;
                const cycles = parseInt(parts[3]) || 0;
                const energyFull = parseInt(parts[4]) || 0;
                const energyDesign = parseInt(parts[5]) || 0;

                root.batteryLevel = level;
                root.batteryCharging = status === "Charging";
                root.batteryPlugged = acOnline || status === "Charging" || (status === "Full" && level >= 95);
                root.batteryCycles = cycles;

                if (energyDesign > 0 && energyFull > 0) {
                    const health = Math.min(100, Math.round((energyFull / energyDesign) * 100));
                    root.batteryHealthPct = health;
                    root.batteryCondition = health >= 80 ? "Normal" : "Service Recommended";
                } else {
                    root.batteryHealthPct = 100;
                    root.batteryCondition = "Normal";
                }

                if (root.batteryCharging) {
                    root.batteryStatusText = "Charging (" + level + "%)";
                    root.batteryIcon = "󰂄";
                } else if (root.batteryPlugged) {
                    root.batteryStatusText = "Plugged In (" + level + "%)";
                    root.batteryIcon = "󰚥";
                } else {
                    root.batteryStatusText = "Discharging (" + level + "%)";
                    if (level >= 90) root.batteryIcon = "󰁹";
                    else if (level >= 70) root.batteryIcon = "󰂁";
                    else if (level >= 50) root.batteryIcon = "󰁿";
                    else if (level >= 30) root.batteryIcon = "󰁽";
                    else if (level >= 10) root.batteryIcon = "󰁻";
                    else root.batteryIcon = "󰂎";
                }
            }
        }
    }

    function refreshBattery() {
        battProc.running = true;
        profileProc.running = true;
    }

    // ── Power Profiles ──────────────────────────────
    property string powerProfile: "balanced"
    property bool _profileSwitching: false

    Process {
        id: profileProc
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._profileSwitching) return;
                const p = text.trim();
                if (p) root.powerProfile = p;
            }
        }
    }

    Process {
        id: setProfileProc
        stdout: StdioCollector {
            onStreamFinished: {
                profileSwitchTimer.start();
            }
        }
    }

    Timer {
        id: profileSwitchTimer
        interval: 350
        onTriggered: {
            root._profileSwitching = false;
            profileProc.running = true;
        }
    }

    Timer {
        id: profileSafetyTimer
        interval: 2500
        onTriggered: {
            root._profileSwitching = false;
            profileProc.running = true;
        }
    }

    function setPowerProfile(profile) {
        if (!profile || powerProfile === profile) return;
        powerProfile = profile;
        _profileSwitching = true;
        profileSwitchTimer.stop();
        profileSafetyTimer.restart();
        setProfileProc.command = ["powerprofilesctl", "set", profile];
        setProfileProc.running = true;
        OsdService.showPowerProfile(profile);
    }

    function cyclePowerProfile() {
        const order = ["power-saver", "balanced", "performance"];
        let idx = order.indexOf(powerProfile);
        if (idx === -1) idx = 1;
        const next = order[(idx + 1) % order.length];
        setPowerProfile(next);
    }

    IpcHandler {
        target: "powerprofile"
        function cycle(): void { root.cyclePowerProfile(); }
        function toggle(): void { root.cyclePowerProfile(); }
        function next(): void { root.cyclePowerProfile(); }
        function set(profile: string): void { root.setPowerProfile(profile); }
    }

    property bool _sysReady: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root._sysReady = true
    }

    onBatteryPluggedChanged: {
        if (_sysReady) {
            OsdService.showPowerSupply(batteryPlugged, batteryLevel);
        }
    }

    // ── Audio Volume ────────────────────────────────
    property int volume: 50
    property bool volumeMuted: false

    // ── Headphone Detection ─────────────────────────
    readonly property bool isHeadphones: {
        // 1. Pipewire defaultAudioSink checks
        const sink = Pipewire.defaultAudioSink;
        if (sink) {
            const desc = (sink.description || "").toLowerCase();
            const name = (sink.name || "").toLowerCase();
            const nick = (sink.nickname || "").toLowerCase();
            const props = sink.properties || {};
            const iconName = ((props["device.icon_name"] || props["device.icon-name"] || "") + "").toLowerCase();
            const formFactor = ((props["device.form_factor"] || "") + "").toLowerCase();

            if (iconName.includes("headphone") || iconName.includes("headset") ||
                formFactor.includes("headphone") || formFactor.includes("headset") || formFactor.includes("earphone") ||
                desc.includes("headphone") || desc.includes("headset") || desc.includes("earphone") || desc.includes("airpod") || desc.includes("buds") ||
                nick.includes("headphone") || nick.includes("headset") || nick.includes("earphone") ||
                name.includes("headphone") || name.includes("headset") || name.includes("bluez")) {
                return true;
            }

            if ((iconName.includes("speaker") || nick.includes("speaker")) && !name.includes("bluez")) {
                let btOrHpActive = false;
                if (root.audioSinks && root.audioSinks.length > 0) {
                    for (let i = 0; i < root.audioSinks.length; i++) {
                        const s = root.audioSinks[i];
                        if (s.active) {
                            const sName = (s.name || "").toLowerCase();
                            if (sName.includes("headphone") || sName.includes("headset") ||
                                sName.includes("earphone") || sName.includes("airpod") ||
                                sName.includes("buds") || sName.includes("bluez")) {
                                btOrHpActive = true;
                                break;
                            }
                        }
                    }
                }
                if (!btOrHpActive) return false;
            }
        }

        // 2. Active audio sink from audioSinks list
        if (root.audioSinks && root.audioSinks.length > 0) {
            for (let i = 0; i < root.audioSinks.length; i++) {
                const s = root.audioSinks[i];
                if (s.active) {
                    const sName = (s.name || "").toLowerCase();
                    if (sName.includes("headphone") || sName.includes("headset") ||
                        sName.includes("earphone") || sName.includes("airpod") ||
                        sName.includes("buds") || sName.includes("bluez")) {
                        return true;
                    }
                }
            }
        }

        // 3. Connected Bluetooth audio devices
        if (root.bluetoothEnabled && root.bluetoothDevices && root.bluetoothDevices.length > 0) {
            for (let i = 0; i < root.bluetoothDevices.length; i++) {
                const d = root.bluetoothDevices[i];
                if (d.connected) {
                    const dIcon = (d.icon || "").toLowerCase();
                    const dName = (d.name || "").toLowerCase();
                    if (dIcon === "headphones" || dIcon === "headset" ||
                        dName.includes("airpod") || dName.includes("headphone") ||
                        dName.includes("headset") || dName.includes("buds") ||
                        dName.includes("earphone") || dName.includes("pro's") || dName.includes("pro’s") || dName.includes("pros")) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    readonly property string volumeIcon: {
        if (volumeMuted) return isHeadphones ? "󰟎" : "󰖁";
        if (isHeadphones) return "󰋋";
        if (volume === 0) return "󰖁";
        return volume > 60 ? "󰕾" : (volume > 20 ? "󰖀" : "󰕿");
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            sinksProc.running = true;
            volProc.running = true;
        }
    }

    // ── Drag & Sync Protection Flags ──────────────
    property bool isVolumeDragging: false
    property bool isMicDragging: false
    property bool isBrightnessDragging: false

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumeChanged() {
            if (!root.isVolumeDragging && Pipewire.defaultAudioSink?.audio) {
                root.volume = Math.round(Pipewire.defaultAudioSink.audio.volume * 100);
                root.volumeMuted = Pipewire.defaultAudioSink.audio.muted;
            }
        }

        function onMutedChanged() {
            if (!root.isVolumeDragging && Pipewire.defaultAudioSink?.audio) {
                root.volume = Math.round(Pipewire.defaultAudioSink.audio.volume * 100);
                root.volumeMuted = Pipewire.defaultAudioSink.audio.muted;
            }
        }
    }

    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null

        function onVolumeChanged() {
            if (!root.isMicDragging && Pipewire.defaultAudioSource?.audio) {
                root.micVolume = Math.round(Pipewire.defaultAudioSource.audio.volume * 100);
                root.micMuted = Pipewire.defaultAudioSource.audio.muted;
            }
        }

        function onMutedChanged() {
            if (!root.isMicDragging && Pipewire.defaultAudioSource?.audio) {
                root.micVolume = Math.round(Pipewire.defaultAudioSource.audio.volume * 100);
                root.micMuted = Pipewire.defaultAudioSource.audio.muted;
            }
        }
    }

    Connections {
        target: OsdService

        function onVolumeUpdated(vol, muted) {
            if (!root.isVolumeDragging) {
                root.volume = vol;
                root.volumeMuted = muted;
            }
        }

        function onMicUpdated(vol, muted) {
            if (!root.isMicDragging) {
                root.micVolume = vol;
                root.micMuted = muted;
            }
        }

        function onBrightnessUpdated(pct) {
            if (!root.isBrightnessDragging) {
                root.brightness = pct;
            }
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%.0f\\n\", $2*100; if ($3==\"[MUTED]\") print \"muted\"; else print \"unmuted\"}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isVolumeDragging) return;
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    root.volume = parseInt(lines[0]) || 0;
                    root.volumeMuted = lines[1] === "muted";
                }
            }
        }
    }

    Process {
        id: volSetProc
        command: ["sh", "-c", ""]
    }

    Timer {
        id: volSyncTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!root.isVolumeDragging) {
                volProc.running = false;
                volProc.running = true;
            }
        }
    }

    property int _pendingSinkVolume: -1

    Timer {
        id: volThrottleTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root._pendingSinkVolume >= 0) {
                const vol = root._pendingSinkVolume;
                root._pendingSinkVolume = -1;
                const frac = Math.max(0, Math.min(1.5, vol / 100)).toFixed(2);
                volSetProc.running = false;
                volSetProc.command = ["sh", "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + frac + (vol === 0 ? " && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1" : " && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0")];
                volSetProc.running = true;
            }
        }
    }

    function flushVolume() {
        if (volThrottleTimer.running) volThrottleTimer.stop();
        if (root._pendingSinkVolume >= 0) {
            const vol = root._pendingSinkVolume;
            root._pendingSinkVolume = -1;
            const frac = Math.max(0, Math.min(1.5, vol / 100)).toFixed(2);
            volSetProc.running = false;
            volSetProc.command = ["sh", "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + frac + (vol === 0 ? " && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1" : " && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0")];
            volSetProc.running = true;
        }
        volSyncTimer.restart();
    }

    Process {
        id: muteSinkProc
        command: ["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%.0f\\n\", $2*100; if ($3==\"[MUTED]\") print \"muted\"; else print \"unmuted\"}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isVolumeDragging) return;
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    root.volume = parseInt(lines[0]) || 0;
                    root.volumeMuted = lines[1] === "muted";
                }
            }
        }
    }

    function adjustVolume(delta) {
        root.volume = Math.max(0, Math.min(150, root.volume + delta));
        root.volumeMuted = (root.volume === 0);
        const sign = delta > 0 ? "+" : "-";
        const abs = Math.abs(delta);
        volSetProc.running = false;
        volSetProc.command = ["sh", "-c", "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ " + abs + "%" + sign + "; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"];
        volSetProc.running = true;
        volSyncTimer.restart();
    }

    function setVolumePercent(pct) {
        const clamped = Math.max(0, Math.min(150, Math.round(pct)));
        root.volume = clamped;
        root.volumeMuted = (clamped === 0);
        root._pendingSinkVolume = clamped;
        if (!volThrottleTimer.running) {
            volThrottleTimer.start();
        }
        volSyncTimer.restart();
    }

    function toggleMute() {
        root.volumeMuted = !root.volumeMuted;
        muteSinkProc.running = false;
        muteSinkProc.running = true;
    }
    // ── Audio Sinks (Outputs) Discovery ──────────
    property var audioSinks: []

    Process {
        id: sinksProc
        command: ["python3", "-c", "import subprocess, re, json\nout = subprocess.check_output(['wpctl', 'status'], text=True)\nsinks_section = False\nsinks = []\nfor line in out.splitlines():\n    if 'Sinks:' in line:\n        sinks_section = True\n        continue\n    if sinks_section:\n        if 'Sources:' in line or 'Filters:' in line or 'Streams:' in line or not line.strip():\n            if sinks: break\n        m = re.search(r'([* ])\\s+(\\d+)\\.\\s+(.*?)(?:\\s+\\[vol:.*\\])?$', line)\n        if m:\n            sinks.append({'id': m.group(2), 'name': m.group(3).strip(), 'active': m.group(1) == '*'})\nprint(json.dumps(sinks))\n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "[]");
                    root.audioSinks = parsed;
                } catch(e) {}
            }
        }
    }

    function rescanAudioSinks() {
        sinksProc.running = true;
    }

    function setAudioSink(sinkId) {
        runCmd("wpctl set-default " + sinkId);
        sinksProc.running = true;
        volProc.running = true;
    }

    // ── Microphone (Input) & Sources Discovery ──
    property int micVolume: 100
    property bool micMuted: false
    property bool micInUse: false
    property string micAppName: ""
    property var audioSources: []

    Process {
        id: micProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{printf \"%.0f\\n\", $2*100; if ($3==\"[MUTED]\") print \"muted\"; else print \"unmuted\"}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.micVolume = parseInt(lines[0]) || 0;
                root.micMuted = lines[1] === "muted";
            }
        }
    }

    Process {
        id: sourcesProc
        command: ["python3", "-c", "import subprocess, re, json\nout = subprocess.check_output(['wpctl', 'status'], text=True)\nsources = []\nin_sources = False\nfor line in out.splitlines():\n    if 'Sources:' in line:\n        in_sources = True\n        continue\n    if in_sources:\n        if 'Filters:' in line or 'Streams:' in line or 'Video' in line:\n            break\n        m = re.search(r'([* ])\\s+(\\d+)\\.\\s+(.*?)(?:\\s+\\[vol:.*\\])?$', line)\n        if m:\n            sources.append({\n                'id': m.group(2),\n                'name': m.group(3).replace('Alder Lake PCH-P High Definition Audio Controller ', '').strip(),\n                'active': m.group(1) == '*'\n            })\nprint(json.dumps(sources))\n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "[]");
                    root.audioSources = parsed;
                } catch(e) {}
            }
        }
    }

    Process {
        id: micUsageProc
        command: ["python3", "-c", "import subprocess\ntry:\n    out = subprocess.check_output(['pactl', 'list', 'source-outputs'], text=True)\n    lines = [l for l in out.splitlines() if 'application.name =' in l]\n    app = lines[0].split('=')[1].strip().strip('\"') if lines else ''\n    print('yes' if lines else 'no')\n    print(app)\nexcept:\n    print('no\\n')\n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.micInUse = lines[0] === "yes";
                root.micAppName = lines.length > 1 ? lines[1] : "";
            }
        }
    }

    Timer {
        interval: root.isIdleOrLocked ? 10000 : 3000
        running: true
        repeat: true
        onTriggered: {
            micUsageProc.running = true;
            micProc.running = true;
        }
    }

    Process {
        id: muteSourceProc
        command: ["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{printf \"%.0f\\n\", $2*100; if ($3==\"[MUTED]\") print \"muted\"; else print \"unmuted\"}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    root.micVolume = parseInt(lines[0]) || 0;
                    root.micMuted = lines[1] === "muted";
                }
            }
        }
    }

    Process {
        id: micSetProc
        command: ["sh", "-c", ""]
    }

    Timer {
        id: micSyncTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!root.isMicDragging) {
                micProc.running = false;
                micProc.running = true;
            }
        }
    }

    property int _pendingSourceVolume: -1

    Timer {
        id: micThrottleTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root._pendingSourceVolume >= 0) {
                const vol = root._pendingSourceVolume;
                root._pendingSourceVolume = -1;
                const frac = Math.max(0, Math.min(1.5, vol / 100)).toFixed(2);
                micSetProc.running = false;
                micSetProc.command = ["sh", "-c", "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ " + frac + (vol === 0 ? " && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1" : " && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0")];
                micSetProc.running = true;
            }
        }
    }

    function flushMicVolume() {
        if (micThrottleTimer.running) micThrottleTimer.stop();
        if (root._pendingSourceVolume >= 0) {
            const vol = root._pendingSourceVolume;
            root._pendingSourceVolume = -1;
            const frac = Math.max(0, Math.min(1.5, vol / 100)).toFixed(2);
            micSetProc.running = false;
            micSetProc.command = ["sh", "-c", "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ " + frac + (vol === 0 ? " && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1" : " && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0")];
            micSetProc.running = true;
        }
        micSyncTimer.restart();
    }

    function adjustMicVolume(delta) {
        root.micVolume = Math.max(0, Math.min(150, root.micVolume + delta));
        root.micMuted = (root.micVolume === 0);
        const sign = delta > 0 ? "+" : "-";
        const abs = Math.abs(delta);
        micSetProc.running = false;
        micSetProc.command = ["sh", "-c", "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SOURCE@ " + abs + "%" + sign + "; wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0"];
        micSetProc.running = true;
        micSyncTimer.restart();
    }

    function setMicVolumePercent(pct) {
        const clamped = Math.max(0, Math.min(150, Math.round(pct)));
        root.micVolume = clamped;
        root.micMuted = (clamped === 0);
        root._pendingSourceVolume = clamped;
        if (!micThrottleTimer.running) {
            micThrottleTimer.start();
        }
        micSyncTimer.restart();
    }

    function toggleMicMute() {
        root.micMuted = !root.micMuted;
        muteSourceProc.running = false;
        muteSourceProc.running = true;
    }

    function rescanAudioSources() {
        sourcesProc.running = true;
        micProc.running = true;
    }

    function setAudioSource(sourceId) {
        runCmd("wpctl set-default " + sourceId);
        sourcesProc.running = true;
        micProc.running = true;
    }

    // ── Per-Application Audio Streams (Mixer) ────
    property var appAudioStreams: []
    property bool isAppVolumeDragging: false

    Process {
        id: appStreamsProc
        command: ["python3", "-c", "import subprocess, json\ntry:\n    out = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sink-inputs'], text=True)\n    data = json.loads(out)\n    streams = []\n    for item in data:\n        idx = item.get('index')\n        props = item.get('properties', {})\n        name = props.get('application.name') or props.get('media.name') or props.get('node.name') or 'Application'\n        icon = props.get('application.icon_name') or ''\n        binary = props.get('application.process.binary') or ''\n        media_name = props.get('media.name') or ''\n        muted = bool(item.get('mute', False))\n        corked = bool(item.get('corked', False))\n        vol_obj = item.get('volume', {})\n        pct = 100\n        for ch in ['front-left', 'mono']:\n            if ch in vol_obj:\n                pct = int(vol_obj[ch].get('value_percent', '100%').replace('%', ''))\n                break\n        else:\n            for ch, v in vol_obj.items():\n                if isinstance(v, dict) and 'value_percent' in v:\n                    pct = int(v['value_percent'].replace('%', ''))\n                    break\n        streams.append({'id': idx, 'name': name, 'icon': icon, 'binary': binary, 'media_name': media_name if media_name != name else '', 'volume': pct, 'muted': muted, 'corked': corked})\n    print(json.dumps(streams))\nexcept:\n    print('[]')\n"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isAppVolumeDragging) return;
                try {
                    const parsed = JSON.parse(text.trim() || "[]");
                    root.appAudioStreams = parsed;
                } catch(e) {}
            }
        }
    }

    Timer {
        id: appStreamPollTimer
        interval: 1200
        running: root.controlCenterOpen && root.controlCenterSubView === "audio"
        repeat: true
        onTriggered: root.rescanAppAudioStreams()
    }

    Timer {
        id: appStreamSyncTimer
        interval: 150
        repeat: false
        onTriggered: root.rescanAppAudioStreams()
    }

    function rescanAppAudioStreams() {
        if (!appStreamsProc.running && !root.isAppVolumeDragging) {
            appStreamsProc.running = true;
        }
    }

    property int _pendingAppStreamId: -1
    property int _pendingAppStreamVol: -1

    Process {
        id: appVolSetProc
        command: ["sh", "-c", ""]
    }

    Timer {
        id: appVolThrottleTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (root._pendingAppStreamId >= 0 && root._pendingAppStreamVol >= 0) {
                const sId = root._pendingAppStreamId;
                const vol = root._pendingAppStreamVol;
                root._pendingAppStreamId = -1;
                root._pendingAppStreamVol = -1;
                const cmd = "pactl set-sink-input-volume " + sId + " " + vol + "%" + (vol === 0 ? " && pactl set-sink-input-mute " + sId + " 1" : " && pactl set-sink-input-mute " + sId + " 0");
                appVolSetProc.running = false;
                appVolSetProc.command = ["sh", "-c", cmd];
                appVolSetProc.running = true;
            }
        }
    }

    function setAppStreamVolume(streamId, pct) {
        const clamped = Math.max(0, Math.min(150, Math.round(pct)));
        root._pendingAppStreamId = streamId;
        root._pendingAppStreamVol = clamped;
        if (!appVolThrottleTimer.running) {
            appVolThrottleTimer.start();
        }
    }

    function flushAppStreamVolume() {
        if (appVolThrottleTimer.running) appVolThrottleTimer.stop();
        if (root._pendingAppStreamId >= 0 && root._pendingAppStreamVol >= 0) {
            const sId = root._pendingAppStreamId;
            const vol = root._pendingAppStreamVol;
            root._pendingAppStreamId = -1;
            root._pendingAppStreamVol = -1;
            const cmd = "pactl set-sink-input-volume " + sId + " " + vol + "%" + (vol === 0 ? " && pactl set-sink-input-mute " + sId + " 1" : " && pactl set-sink-input-mute " + sId + " 0");
            appVolSetProc.running = false;
            appVolSetProc.command = ["sh", "-c", cmd];
            appVolSetProc.running = true;
        }
        appStreamSyncTimer.restart();
    }

    Process {
        id: appMuteProc
        command: ["sh", "-c", ""]
    }

    function toggleAppStreamMute(streamId) {
        appMuteProc.running = false;
        appMuteProc.command = ["sh", "-c", "pactl set-sink-input-mute " + streamId + " toggle"];
        appMuteProc.running = true;
        appStreamSyncTimer.restart();
    }

    // ── Display Brightness ──────────────────────────
    property int brightness: 100

    Process {
        id: brightProc
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%' || echo '100'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isBrightnessDragging) return;
                const val = parseInt(text.trim());
                root.brightness = isNaN(val) ? 100 : Math.max(0, Math.min(100, val));
            }
        }
    }

    Process {
        id: brightSetProc
        command: ["sh", "-c", ""]
    }

    Timer {
        id: brightSyncTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!root.isBrightnessDragging) {
                brightProc.running = false;
                brightProc.running = true;
            }
        }
    }

    property int _pendingBrightness: -1

    Timer {
        id: brightThrottleTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root._pendingBrightness >= 0) {
                const b = root._pendingBrightness;
                root._pendingBrightness = -1;
                brightSetProc.running = false;
                brightSetProc.command = ["sh", "-c", "brightnessctl -n set " + b + "%"];
                brightSetProc.running = true;
            }
        }
    }

    function flushBrightness() {
        if (brightThrottleTimer.running) brightThrottleTimer.stop();
        if (root._pendingBrightness >= 0) {
            const b = root._pendingBrightness;
            root._pendingBrightness = -1;
            brightSetProc.running = false;
            brightSetProc.command = ["sh", "-c", "brightnessctl -n set " + b + "%"];
            brightSetProc.running = true;
        }
        brightSyncTimer.restart();
    }

    function adjustBrightness(delta) {
        root.brightness = Math.max(0, Math.min(100, root.brightness + delta));
        const sign = delta > 0 ? "+" : "-";
        const abs = Math.abs(delta);
        brightSetProc.running = false;
        brightSetProc.command = ["sh", "-c", "brightnessctl -n set " + abs + "%" + sign];
        brightSetProc.running = true;
        brightSyncTimer.restart();
    }

    function setBrightnessPercent(pct) {
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        root.brightness = clamped;
        root._pendingBrightness = clamped;
        if (!brightThrottleTimer.running) {
            brightThrottleTimer.start();
        }
        brightSyncTimer.restart();
    }

    // ── Wi-Fi ───────────────────────────────────────
    property string networkType: "disconnected"
    property string networkInfo: "Disconnected"
    property bool wifiEnabled: true
    property bool wifiScanning: false
    property bool wifiConnected: false
    property string wifiSsid: ""
    property string wifiInterface: "wlan0"
    property var wifiActiveNetwork: null
    property var wifiKnownNetworks: []
    property var wifiOtherNetworks: []
    property var wifiNetworks: []
    property var wifiSavedProfiles: []
    property string wifiConnectingSsid: ""
    property string wifiConnectError: ""
    property bool wifiConnecting: false

    // Live Wi-Fi Download / Upload Speeds
    property real wifiRxSpeed: 0
    property real wifiTxSpeed: 0
    property string wifiRxFormatted: "0 B/s"
    property string wifiTxFormatted: "0 B/s"
    property real _lastWifiRx: 0
    property real _lastWifiTx: 0
    property real _lastWifiTime: 0

    function formatSpeed(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec <= 0) return "0 B/s";
        if (bytesPerSec < 1024) return Math.round(bytesPerSec) + " B/s";
        if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + " KB/s";
        if (bytesPerSec < 1024 * 1024 * 1024) return (bytesPerSec / (1024 * 1024)).toFixed(1) + " MB/s";
        return (bytesPerSec / (1024 * 1024 * 1024)).toFixed(2) + " GB/s";
    }

    readonly property string wifiBarIcon: {
        if (networkType === "ethernet") return "󰈀";
        if (!wifiEnabled) return "󰖪";
        return "";
    }

    Process {
        id: netProc
        command: ["sh", "-c", "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected'); if [ -n \"$eth\" ]; then echo 'ethernet:Ethernet'; else wifi_radio=$(nmcli radio wifi 2>/dev/null); if [ \"$wifi_radio\" = 'disabled' ]; then echo 'off:'; else wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | head -1 | cut -d: -f2-); if [ -n \"$wifi\" ]; then echo \"wifi:$wifi\"; else echo 'disconnected:'; fi; fi; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                const idx = result.indexOf(':');
                if (idx !== -1) {
                    const type = result.substring(0, idx);
                    const info = result.substring(idx + 1);
                    if (type === "ethernet") {
                        root.networkType = "ethernet";
                        root.networkInfo = "Ethernet";
                    } else if (type === "wifi") {
                        const wasDisconnected = !root.wifiConnected;
                        root.networkType = "wifi";
                        root.networkInfo = info || "Connected";
                        root.wifiConnected = true;
                        root.wifiEnabled = true;
                        root.wifiSsid = info;
                        if (wasDisconnected && !root.controlCenterOpen) {
                            wifiStatusProc.running = true;
                        }
                    } else if (type === "off") {
                        root.networkType = "disconnected";
                        root.networkInfo = "Wi-Fi Off";
                        root.wifiEnabled = false;
                        root.wifiConnected = false;
                        root.wifiSsid = "";
                        root.wifiActiveNetwork = null;
                    } else {
                        root.networkType = "disconnected";
                        root.networkInfo = "Disconnected";
                        root.wifiEnabled = true;
                        root.wifiConnected = false;
                        root.wifiSsid = "";
                        root.wifiActiveNetwork = null;
                    }
                }
            }
        }
    }

    Process {
        id: wifiStatusProc
        command: ["/home/aran/.config/quickshell/scripts/wifi.sh", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    root.wifiEnabled = !!data.enabled;
                    root.wifiScanning = !!data.scanning;
                    root.wifiConnected = !!data.connected;
                    root.wifiInterface = data.interface || "wlan0";
                    root.wifiActiveNetwork = data.active || null;
                    root.wifiSsid = (data.active && data.active.ssid) ? data.active.ssid : "";
                    root.wifiKnownNetworks = data.known_networks || [];
                    root.wifiOtherNetworks = data.other_networks || [];
                    root.wifiNetworks = data.all_networks || [];
                    root.wifiSavedProfiles = data.saved_profiles || [];

                    if (root.networkType !== "ethernet") {
                        if (root.wifiConnected && root.wifiSsid) {
                            root.networkType = "wifi";
                            root.networkInfo = root.wifiSsid;
                        } else if (!root.wifiEnabled) {
                            root.networkType = "disconnected";
                            root.networkInfo = "Wi-Fi Off";
                        } else {
                            root.networkType = "disconnected";
                            root.networkInfo = "Disconnected";
                        }
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: wifiActionProc
        command: ["sh", "-c", ""]
    }

    Process {
        id: wifiConnectProc
        command: ["sh", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiConnecting = false;
                try {
                    const res = JSON.parse(text.trim());
                    if (res.success) {
                        root.wifiConnectingSsid = "";
                        root.wifiConnectError = "";
                    } else {
                        root.wifiConnectError = res.error || "Failed to connect";
                    }
                } catch(e) {
                    root.wifiConnectError = text.trim() || "Connection failed";
                }
                wifiRefreshTimer.start();
            }
        }
    }

    Timer {
        id: wifiRefreshTimer
        interval: 350
        repeat: false
        onTriggered: {
            wifiStatusProc.running = true;
            netProc.running = true;
        }
    }

    // Faster polling when wifi view is open
    Timer {
        id: wifiScanPollTimer
        interval: 3000
        running: root.controlCenterOpen && root.controlCenterSubView === "wifi"
        repeat: true
        onTriggered: wifiStatusProc.running = true
    }

    Timer {
        id: scanDoneTimer
        interval: 2200
        repeat: false
        onTriggered: {
            root.wifiScanning = false;
            wifiStatusProc.running = true;
        }
    }

    Process {
        id: wifiSpeedProc
        command: ["sh", "-c", "awk -v iface=\"" + (root.wifiInterface || "wlan0") + "\" '$1 ~ (\"^\"iface\":\") {print $2, $10}' /proc/net/dev"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length >= 2) {
                    const rx = parseFloat(parts[0]) || 0;
                    const tx = parseFloat(parts[1]) || 0;
                    const now = Date.now();
                    if (root._lastWifiTime > 0 && root._lastWifiRx > 0) {
                        const dt = (now - root._lastWifiTime) / 1000.0;
                        if (dt > 0.4 && dt < 8.0 && rx >= root._lastWifiRx && tx >= root._lastWifiTx) {
                            const rxRate = (rx - root._lastWifiRx) / dt;
                            const txRate = (tx - root._lastWifiTx) / dt;
                            root.wifiRxSpeed = rxRate;
                            root.wifiTxSpeed = txRate;
                            root.wifiRxFormatted = root.formatSpeed(rxRate);
                            root.wifiTxFormatted = root.formatSpeed(txRate);
                        }
                    }
                    root._lastWifiRx = rx;
                    root._lastWifiTx = tx;
                    root._lastWifiTime = now;
                }
            }
        }
    }

    Timer {
        id: wifiSpeedTimer
        interval: 1000
        running: root.controlCenterOpen && root.controlCenterSubView === "wifi" && (root.wifiConnected || root.networkType === "wifi")
        repeat: true
        onTriggered: wifiSpeedProc.running = true
    }

    function runWifiAction(action, arg1, arg2) {
        let cmd = "/home/aran/.config/quickshell/scripts/wifi.sh " + action;
        if (arg1) cmd += " '" + arg1 + "'";
        if (arg2) cmd += " '" + arg2 + "'";
        wifiActionProc.command = ["sh", "-c", "(" + cmd + ") &"];
        wifiActionProc.running = true;
        wifiRefreshTimer.start();
    }

    function toggleWifi() {
        const next = !wifiEnabled;
        wifiEnabled = next;
        if (!next) {
            wifiConnected = false;
            wifiActiveNetwork = null;
            if (networkType !== "ethernet") {
                networkType = "disconnected";
                networkInfo = "Wi-Fi Off";
            }
        }
        runWifiAction(next ? "on" : "off");
    }

    function rescanWifi() {
        if (!wifiEnabled) return;
        wifiScanning = true;
        wifiActionProc.command = ["sh", "-c", "(/home/aran/.config/quickshell/scripts/wifi.sh rescan) &"];
        wifiActionProc.running = true;
        scanDoneTimer.start();
    }

    function connectWifi(ssid) {
        if (!ssid) return;
        wifiConnecting = true;
        wifiConnectingSsid = ssid;
        wifiConnectError = "";
        wifiConnectProc.command = ["/home/aran/.config/quickshell/scripts/wifi.sh", "connect", ssid];
        wifiConnectProc.running = true;
    }

    function connectWifiWithPassword(ssid, password) {
        if (!ssid) return;
        wifiConnecting = true;
        wifiConnectingSsid = ssid;
        wifiConnectError = "";
        wifiConnectProc.command = ["/home/aran/.config/quickshell/scripts/wifi.sh", "connect", ssid, password];
        wifiConnectProc.running = true;
    }

    function connectHiddenWifi(ssid, password) {
        if (!ssid) return;
        wifiConnecting = true;
        wifiConnectingSsid = ssid;
        wifiConnectError = "";
        wifiConnectProc.command = ["/home/aran/.config/quickshell/scripts/wifi.sh", "connect-hidden", ssid, password || ""];
        wifiConnectProc.running = true;
    }

    function disconnectWifi() {
        wifiConnected = false;
        wifiActiveNetwork = null;
        if (networkType !== "ethernet") {
            networkType = "disconnected";
            networkInfo = "Disconnected";
        }
        runWifiAction("disconnect");
    }

    function forgetWifi(ssid) {
        if (!ssid) return;
        runWifiAction("forget", ssid);
    }

    function refreshWifi() {
        wifiStatusProc.running = true;
    }

    // ── Bluetooth ───────────────────────────────────
    property bool bluetoothEnabled: false
    property bool bluetoothDiscovering: false
    property bool bluetoothDiscoverable: false
    property string bluetoothAdapterName: "Bluetooth"
    property var bluetoothDevices: []
    property var bluetoothAvailableDevices: []

    Process {
        id: btStatusProc
        command: ["/home/aran/.config/quickshell/scripts/bluetooth.sh", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    root.bluetoothEnabled = !!data.enabled;
                    root.bluetoothDiscovering = !!data.discovering;
                    root.bluetoothDiscoverable = !!data.discoverable;
                    if (data.name) root.bluetoothAdapterName = data.name;
                    root.bluetoothDevices = data.paired || [];
                    root.bluetoothAvailableDevices = data.available || [];
                } catch(e) {}
            }
        }
    }

    Process {
        id: btActionProc
        command: ["sh", "-c", ""]
    }

    Timer {
        id: btRefreshTimer
        interval: 350
        repeat: false
        onTriggered: btStatusProc.running = true
    }

    // Faster polling when bluetooth view is open & scanning
    Timer {
        id: btScanPollTimer
        interval: 1800
        running: root.controlCenterOpen && root.controlCenterSubView === "bluetooth" && root.bluetoothDiscovering
        repeat: true
        onTriggered: btStatusProc.running = true
    }

    function runBtAction(action, arg) {
        let cmd = "/home/aran/.config/quickshell/scripts/bluetooth.sh " + action;
        if (arg) cmd += " '" + arg + "'";
        btActionProc.command = ["sh", "-c", "(" + cmd + ") &"];
        btActionProc.running = true;
        btRefreshTimer.start();
    }

    function toggleBluetooth() {
        const next = !bluetoothEnabled;
        bluetoothEnabled = next;
        if (!next) {
            bluetoothDiscovering = false;
            stopBluetoothScan();
        }
        runBtAction(next ? "on" : "off");
    }

    function rescanBluetooth() {
        if (!bluetoothEnabled) return;
        runBtAction("scan-toggle");
    }

    function refreshBluetooth() {
        btStatusProc.running = true;
    }

    function startBluetoothScan() {
        if (!bluetoothEnabled) return;
        runBtAction("scan-start");
    }

    function stopBluetoothScan() {
        runBtAction("scan-stop");
    }

    function toggleBluetoothDiscoverable() {
        bluetoothDiscoverable = !bluetoothDiscoverable;
        runBtAction("discoverable-toggle");
    }

    function connectBluetooth(mac) {
        runBtAction("connect", mac);
    }

    function disconnectBluetooth(mac) {
        runBtAction("disconnect", mac);
    }

    function pairBluetooth(mac) {
        runBtAction("pair", mac);
    }

    function removeBluetooth(mac) {
        runBtAction("remove", mac);
    }

    onControlCenterOpenChanged: {
        if (controlCenterOpen) {
            monitorsProc.running = true;
        } else {
            Services.OverlayCoordinator.releaseExclusiveSurface("controlCenter");
        }
        if (!controlCenterOpen && bluetoothDiscovering) {
            stopBluetoothScan();
        }
        if (controlCenterOpen && controlCenterSubView === "wifi") {
            wifiSpeedProc.running = true;
        }
    }

    onControlCenterSubViewChanged: {
        if (controlCenterOpen && controlCenterSubView === "wifi") {
            wifiSpeedProc.running = true;
        }
    }

    // ── Main Polling Loop ───────────────────────────
    Timer {
        interval: root.isIdleOrLocked ? 10000 : 2500
        running: true
        repeat: true
        property int tick: 0
        onTriggered: {
            tick++;
            cpuProc.running = true;
            memProc.running = true;
            tempProc.running = true;
            netProc.running = true;
            battProc.running = true;
            profileProc.running = true;
            volProc.running = true;
            sinksProc.running = true;
            brightProc.running = true;
            btStatusProc.running = true;
            if (controlCenterOpen || tick % 4 === 0) {
                wifiStatusProc.running = true;
            }
        }
    }
}
