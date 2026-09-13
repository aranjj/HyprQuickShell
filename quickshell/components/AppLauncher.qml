import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../bar" as Bar
import "../services" as Services

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    property int selectedIndex: 0
    property var results: []
    property string searchQuery: ""
    property string activeCategory: "apps" // Default to Apps tab (Launchpad behavior)
    property var hyprWindows: []

    // ── Hyprland Configured Default Programs ─────────
    readonly property string terminalApp: Services.SystemService.defaultTerminal || "kitty"
    readonly property string browserApp: Services.SystemService.defaultBrowser || "firefox"
    readonly property string fileManagerApp: Services.SystemService.defaultFileManager || "dolphin"
    readonly property string terminalName: terminalApp ? (terminalApp.charAt(0).toUpperCase() + terminalApp.slice(1)) : "Terminal"
    readonly property string browserName: browserApp ? (browserApp.charAt(0).toUpperCase() + browserApp.slice(1)) : "Browser"
    readonly property string fileManagerName: fileManagerApp ? (fileManagerApp.charAt(0).toUpperCase() + fileManagerApp.slice(1)) : "File Manager"

    // ── Category List Definition ──────────────────────
    readonly property var categoryList: [
        { id: "all", label: "All", icon: "󰍉" },
        { id: "apps", label: "Apps", icon: "󰣆" },
        { id: "windows", label: "Windows", icon: "󰖲" },
        { id: "commands", label: "Commands", icon: "󰞷" },
        { id: "shortcuts", label: "Shortcuts", icon: "󰅌" },
        { id: "math", label: "Math", icon: "󰃬" }
    ]

    readonly property string searchPlaceholder: {
        switch (activeCategory) {
            case "apps": return "Search Applications (e.g. " + root.terminalName + ", " + root.browserName + ")...";
            case "windows": return "Search Open Windows...";
            case "commands": return "Search or Type Commands (e.g. btop, pacman)...";
            case "shortcuts": return "Search System Shortcuts (e.g. Lock, Screenshot)...";
            case "math": return "Calculate (e.g. 15% of 850, sqrt(144))...";
            case "all":
            default: return "Spotlight Search...";
        }
    }

    function cycleCategory(direction) {
        const list = categoryList;
        let idx = list.findIndex(c => c.id === root.activeCategory);
        if (idx === -1) idx = 1;
        let nextIdx = (idx + direction + list.length) % list.length;
        root.activeCategory = list[nextIdx].id;
        root.selectedIndex = 0;
        root.updateSearchResults();
    }

    // ── Hyprland Windows Provider ────────────────────
    Process {
        id: windowsProc
        command: ["hyprctl", "-i", "0", "-j", "clients"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseHyprlandWindows(text);
            }
        }
    }

    Timer {
        id: fetchTimer
        interval: 150
        repeat: false
        onTriggered: root.fetchWindows()
    }

    function fetchWindows() {
        windowsProc.running = false;
        windowsProc.running = true;
    }

    function parseHyprlandWindows(jsonStr) {
        try {
            const raw = JSON.parse(jsonStr.trim() || "[]");
            let list = [];
            for (let i = 0; i < raw.length; i++) {
                const w = raw[i];
                if (!w || !w.mapped || w.hidden) continue;
                const cls = (w.class || w.initialClass || "").toLowerCase();
                if (cls === "quickshell" || cls === "") continue;

                list.push({
                    id: "win_" + w.address,
                    type: "window",
                    address: w.address,
                    title: w.title || w.initialTitle || "Untitled Window",
                    clazz: w.class || w.initialClass || "Window",
                    workspaceId: w.workspace ? w.workspace.id : 1,
                    workspaceName: w.workspace ? (w.workspace.name || String(w.workspace.id)) : "1",
                    floating: !!w.floating,
                    pid: w.pid || 0,
                    xwayland: !!w.xwayland
                });
            }
            root.hyprWindows = list;
            if (launcherPanel.visible && (root.activeCategory === "windows" || root.activeCategory === "all")) {
                root.updateSearchResults();
            }
        } catch (e) {
            console.warn("Failed to parse hyprland windows:", e);
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (launcherPanel.visible) {
                root.fetchWindows();
            }
        }
    }

    function focusWindow(address) {
        Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.focus({ window = \"address:" + address + "\" })'");
        closeLauncher();
    }

    function closeWindow(address) {
        Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.window.close({ window = \"address:" + address + "\" })'");
        root.hyprWindows = root.hyprWindows.filter(w => w.address !== address);
        root.updateSearchResults();
        fetchTimer.restart();
    }

    function toggleWindowFloat(address) {
        Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.focus({ window = \"address:" + address + "\" })' && hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'");
        closeLauncher();
    }

    function makeWindowResultItem(w, category) {
        const wsText = "Workspace " + w.workspaceName;
        const sub = w.clazz + " • " + wsText + (w.floating ? " • Floating" : "");
        return {
            id: "win_" + w.address,
            type: "window",
            address: w.address,
            title: w.title,
            subtitle: sub,
            category: category || "OPEN WINDOWS",
            kindTag: wsText,
            icon: (w.clazz || "").toLowerCase(),
            glyph: "󰖲",
            accentColor: "#89b4fa",
            wsName: w.workspaceName,
            wsId: w.workspaceId,
            clazz: w.clazz,
            floating: w.floating,
            pid: w.pid,
            desc: "Active window on " + wsText + ". Press Enter to switch, or Ctrl+W to close.",
            actionLabel: "Switch to Window",
            action: () => root.focusWindow(w.address)
        };
    }

    function makeWebSearchItem(rawQ) {
        return {
            id: "web_search_" + rawQ,
            type: "web",
            title: "Search Google for \"" + rawQ + "\"",
            subtitle: "Search on the web in default browser",
            category: "WEB SEARCH",
            kindTag: "Web Search",
            icon: "󰖟",
            glyph: "󰖟",
            accentColor: root.theme.accent,
            desc: "Performs a Google web search in your default web browser.",
            actionLabel: "Search Web",
            action: () => root.searchWeb(rawQ)
        };
    }

    // ── IPC Handler for External Toggle ─────────────
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (launcherPanel.visible) {
                root.closeLauncher();
            } else {
                root.openLauncher();
            }
        }

        function open(): void {
            root.openLauncher();
        }

        function query(text: string): void {
            root.openLauncher(text);
        }

        function setCategory(cat: string): void {
            if (!launcherPanel.visible) launcherPanel.visible = true;
            root.activeCategory = cat || "apps";
            root.selectedIndex = 0;
            root.updateSearchResults();
            searchInput.forceActiveFocus();
        }

        function close(): void {
            root.closeLauncher();
        }
    }

    function openLauncher(initialText) {
        launcherPanel.visible = true;
        const text = initialText || "";
        searchInput.text = text;
        if (text.startsWith(">")) {
            root.activeCategory = "commands";
        } else if (text && root.evaluateMath(text) !== "" && (/[+\-*/^%=]|sqrt|sin|cos|tan|pi/i.test(text) || text.startsWith("="))) {
            root.activeCategory = "math";
        } else {
            root.activeCategory = "apps"; // Default to Apps tab like Launchpad!
        }
        root.selectedIndex = 0;
        root.fetchWindows();
        root.updateSearchResults();
        searchInput.forceActiveFocus();
    }

    function closeLauncher() {
        launcherPanel.visible = false;
    }

    // ── Math / Calculator Evaluation ─────────────────
    function evaluateMath(expr) {
        if (!expr) return "";
        let clean = expr.trim();
        if (clean.startsWith("=")) clean = clean.substring(1).trim();
        if (!clean) return "";

        // Transform percentages and powers
        clean = clean.replace(/([0-9.]+)%\s*(?:of|\*)\s*([0-9.]+)/gi, "($1/100)*$2");
        clean = clean.replace(/([0-9.]+)%/g, "($1/100)");
        clean = clean.replace(/\^/g, "**");
        clean = clean.replace(/sqrt\(/gi, "Math.sqrt(");
        clean = clean.replace(/sin\(/gi, "Math.sin(");
        clean = clean.replace(/cos\(/gi, "Math.cos(");
        clean = clean.replace(/tan\(/gi, "Math.tan(");
        clean = clean.replace(/log\(/gi, "Math.log10(");
        clean = clean.replace(/ln\(/gi, "Math.log(");
        clean = clean.replace(/pi\b/gi, "Math.PI");
        clean = clean.replace(/\be\b/gi, "Math.E");
        clean = clean.replace(/abs\(/gi, "Math.abs(");
        clean = clean.replace(/round\(/gi, "Math.round(");

        // Security / token validation
        if (!/^[0-9+\-*/().%*\s,a-zA-Z_]+$/.test(clean)) return "";
        if (/import|require|process|global|window|document|eval|Function|while|for|if|else|return|var|let|const/i.test(clean)) return "";

        try {
            const res = Function('"use strict"; return (' + clean + ')')();
            if (typeof res === "number" && !isNaN(res) && isFinite(res)) {
                if (Number.isInteger(res)) return String(res);
                return String(Math.round(res * 1000000) / 1000000);
            }
        } catch (e) {}
        return "";
    }

    // ── Execution Helpers ────────────────────────────
    function runTerminalCmd(cmd, hold) {
        Services.SystemService.runInTerminal(cmd, hold);
        closeLauncher();
    }

    function runBgCmd(cmd) {
        const clean = cmd.trim();
        if (!clean) return;
        Services.SystemService.runCmd(clean);
        closeLauncher();
    }

    function searchWeb(query) {
        const q = encodeURIComponent(query.trim());
        if (!q) return;
        const browser = root.browserApp || "firefox";
        Services.SystemService.runCmd("xdg-open 'https://www.google.com/search?q=" + q + "' || " + browser + " 'https://www.google.com/search?q=" + q + "'");
        closeLauncher();
    }

    function copyToClipboard(text) {
        Services.SystemService.runCmd("printf '%s' " + JSON.stringify(text) + " | wl-copy");
        closeLauncher();
    }

    // ── Built-in System Shortcuts Library ────────────
    readonly property var systemShortcuts: [
        {
            id: "sc_clipboard",
            title: "Clipboard History",
            subtitle: "Browse and paste recent clipboard clips",
            category: "SHORTCUTS",
            kindTag: "Desktop Shortcut",
            icon: "󰅌",
            glyph: "󰅌",
            accentColor: "#a371f7",
            keys: ["SUPER", "V"],
            desc: "Opens the clipboard manager to view, search, and paste copied items.",
            actionLabel: "Open Clipboard",
            keywords: ["clipboard", "copy", "paste", "cliphist", "history"],
            action: () => Services.SystemService.runCmd("quickshell ipc call clipboard toggle")
        },
        {
            id: "sc_lock",
            title: "Lock Screen",
            subtitle: "Lock current session and display lock screen",
            category: "SHORTCUTS",
            kindTag: "Security",
            icon: "󰌾",
            glyph: "󰌾",
            accentColor: "#f38ba8",
            keys: ["SUPER", "L"],
            desc: "Locks the active desktop session and protects your workspace.",
            actionLabel: "Lock Screen",
            keywords: ["lock", "lockscreen", "screen", "protect"],
            action: () => Services.SystemService.lockScreen()
        },
        {
            id: "sc_controlcenter",
            title: "Control Center",
            subtitle: "Open macOS-style Quick Settings and sliders",
            category: "SHORTCUTS",
            kindTag: "System Settings",
            icon: "󰒓",
            glyph: "󰒓",
            accentColor: "#89b4fa",
            keys: ["SUPER", "C"],
            desc: "Access volume, brightness, Wi-Fi, Bluetooth, battery, and media controls.",
            actionLabel: "Open Control Center",
            keywords: ["settings", "control", "center", "sliders", "quick"],
            action: () => Services.SystemService.openControlCenter("controls", "main")
        },
        {
            id: "sc_wifi",
            title: "Wi-Fi Settings",
            subtitle: "Manage wireless networks and live throughput",
            category: "SHORTCUTS",
            kindTag: "Network Control",
            icon: "󰖩",
            glyph: "󰖩",
            accentColor: "#a6e3a1",
            keys: ["WI-FI"],
            desc: "Scan nearby access points, join networks, and view live bandwidth speeds.",
            actionLabel: "Open Wi-Fi Panel",
            keywords: ["wifi", "wireless", "network", "internet", "ssid"],
            action: () => Services.SystemService.openControlCenter("controls", "wifi")
        },
        {
            id: "sc_bluetooth",
            title: "Bluetooth Settings",
            subtitle: "Pair, connect, and manage Bluetooth devices",
            category: "SHORTCUTS",
            kindTag: "Device Control",
            icon: "󰂯",
            glyph: "󰂯",
            accentColor: "#89dceb",
            keys: ["BT"],
            desc: "Discover discoverable headphones, controllers, keyboards, and mice.",
            actionLabel: "Open Bluetooth Panel",
            keywords: ["bluetooth", "bt", "devices", "pair", "headphones"],
            action: () => Services.SystemService.openControlCenter("controls", "bluetooth")
        },
        {
            id: "sc_audio",
            title: "Audio & Volume Controls",
            subtitle: "Manage playback streams, visualizer, and sinks",
            category: "SHORTCUTS",
            kindTag: "Sound Settings",
            icon: "󰕾",
            glyph: "󰕾",
            accentColor: "#fab387",
            keys: ["VOL"],
            desc: "Adjust master volume, per-app playback levels, and audio output sinks.",
            actionLabel: "Open Audio Panel",
            keywords: ["volume", "sound", "audio", "speaker", "mute"],
            action: () => Services.SystemService.openControlCenter("controls", "audio")
        },
        {
            id: "sc_wallpaper_picker",
            title: "Wallpaper Picker",
            subtitle: "Browse wallpapers and dynamic theme palettes",
            category: "SHORTCUTS",
            kindTag: "Customization",
            icon: "󰸉",
            glyph: "󰸉",
            accentColor: "#cba6f7",
            keys: ["SUPER", "W"],
            desc: "Visually select wallpapers and automatically regenerate theme accents.",
            actionLabel: "Pick Wallpaper",
            keywords: ["wallpaper", "background", "picker", "theme"],
            action: () => Services.SystemService.runCmd("quickshell ipc call wallpaper picker")
        },
        {
            id: "sc_wallpaper_random",
            title: "Random Wallpaper",
            subtitle: "Shuffle to a random background image",
            category: "SHORTCUTS",
            kindTag: "Customization",
            icon: "󰒝",
            glyph: "󰒝",
            accentColor: "#f9e2af",
            keys: ["SUPER", "ALT", "W"],
            desc: "Picks a random wallpaper from your library and extracts color accents.",
            actionLabel: "Shuffle Wallpaper",
            keywords: ["wallpaper", "random", "shuffle"],
            action: () => Services.SystemService.runCmd("quickshell ipc call wallpaper random")
        },
        {
            id: "sc_nightlight",
            title: "Night Light Filter",
            subtitle: "Toggle warm display color temperature (gammastep)",
            category: "SHORTCUTS",
            kindTag: "Display",
            icon: "󰛨",
            glyph: "󰛨",
            accentColor: "#fab387",
            keys: ["SUPER", "SHIFT", "N"],
            desc: "Reduces blue light exposure in the evening for comfortable viewing.",
            actionLabel: "Toggle Night Light",
            keywords: ["night", "light", "blue", "gamma", "warm"],
            action: () => Services.SystemService.runCmd("quickshell ipc call nightlight toggle")
        },
        {
            id: "sc_screenshot_region",
            title: "Screenshot Selection",
            subtitle: "Select a rectangular area of the screen to capture",
            category: "SHORTCUTS",
            kindTag: "Screen Capture",
            icon: "󰹑",
            glyph: "󰹑",
            accentColor: "#a6e3a1",
            keys: ["PRINT"],
            desc: "Interactive slurp region capture saved to disk and clipboard.",
            actionLabel: "Capture Region",
            keywords: ["screenshot", "snipping", "capture", "region", "area"],
            action: () => Services.SystemService.runCmd("/home/aran/.config/quickshell/scripts/screenshot.sh region")
        },
        {
            id: "sc_screenshot_window",
            title: "Screenshot Window",
            subtitle: "Capture active focused window",
            category: "SHORTCUTS",
            kindTag: "Screen Capture",
            icon: "󰖲",
            glyph: "󰖲",
            accentColor: "#89b4fa",
            keys: ["SUPER", "PRINT"],
            desc: "Captures the active window boundaries with clean transparent padding.",
            actionLabel: "Capture Window",
            keywords: ["screenshot", "window", "capture"],
            action: () => Services.SystemService.runCmd("/home/aran/.config/quickshell/scripts/screenshot.sh window")
        },
        {
            id: "sc_screenshot_screen",
            title: "Screenshot Fullscreen",
            subtitle: "Capture entire display output",
            category: "SHORTCUTS",
            kindTag: "Screen Capture",
            icon: "󰍹",
            glyph: "󰍹",
            accentColor: "#fab387",
            keys: ["SHIFT", "PRINT"],
            desc: "Captures all active monitors and saves immediately to pictures.",
            actionLabel: "Capture Screen",
            keywords: ["screenshot", "fullscreen", "display"],
            action: () => Services.SystemService.runCmd("/home/aran/.config/quickshell/scripts/screenshot.sh fullscreen")
        },
        {
            id: "sc_screenshot_toolbar",
            title: "Screenshot Toolbar",
            subtitle: "Open macOS-style interactive screenshot HUD",
            category: "SHORTCUTS",
            kindTag: "Screen Capture",
            icon: "󰄀",
            glyph: "󰄀",
            accentColor: "#cba6f7",
            keys: ["SUPER", "ALT", "S"],
            desc: "Floating toolbar with Area, Window, Screen, and Timer options.",
            actionLabel: "Open HUD",
            keywords: ["screenshot", "toolbar", "hud"],
            action: () => Services.SystemService.runCmd("quickshell ipc -p /home/aran/.config/quickshell/shell.qml call screenshot toolbar")
        },
        {
            id: "sc_float",
            title: "Toggle Window Floating",
            subtitle: "Toggle floating state of active window",
            category: "SHORTCUTS",
            kindTag: "Window Management",
            icon: "󰉈",
            glyph: "󰉈",
            accentColor: "#94e2d5",
            keys: ["SUPER", "T"],
            desc: "Switches the focused window between tiled layout and floating mode.",
            actionLabel: "Toggle Float",
            keywords: ["float", "window", "tile"],
            action: () => Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'")
        },
        {
            id: "sc_fullscreen",
            title: "Toggle Fullscreen",
            subtitle: "Maximize focused window to fullscreen",
            category: "SHORTCUTS",
            kindTag: "Window Management",
            icon: "󰊓",
            glyph: "󰊓",
            accentColor: "#89b4fa",
            keys: ["SUPER", "F"],
            desc: "Toggles full monitor coverage for the active window.",
            actionLabel: "Toggle Fullscreen",
            keywords: ["fullscreen", "maximize"],
            action: () => Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.fullscreen()'")
        },
        {
            id: "sc_close",
            title: "Close Active Window",
            subtitle: "Close or kill the focused application",
            category: "SHORTCUTS",
            kindTag: "Window Management",
            icon: "󰅖",
            glyph: "󰅖",
            accentColor: "#f38ba8",
            keys: ["SUPER", "C"],
            desc: "Sends a graceful close request to the current window.",
            actionLabel: "Close Window",
            keywords: ["close", "kill", "quit", "window"],
            action: () => Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.window.close()'")
        },
        {
            id: "sc_suspend",
            title: "Sleep / Suspend",
            subtitle: "Put computer into low-power sleep mode",
            category: "SHORTCUTS",
            kindTag: "Power Control",
            icon: "󰤄",
            glyph: "󰤄",
            accentColor: "#89dceb",
            keys: ["SLEEP"],
            desc: "Suspends the operating system to RAM.",
            actionLabel: "Suspend System",
            keywords: ["sleep", "suspend", "standby"],
            action: () => Services.SystemService.runCmd("systemctl suspend")
        },
        {
            id: "sc_reboot",
            title: "Restart Computer",
            subtitle: "Reboot operating system",
            category: "SHORTCUTS",
            kindTag: "Power Control",
            icon: "󰜉",
            glyph: "󰜉",
            accentColor: "#fab387",
            keys: ["REBOOT"],
            desc: "Performs a clean reboot of Linux and all services.",
            actionLabel: "Restart",
            keywords: ["reboot", "restart"],
            action: () => Services.SystemService.runCmd("systemctl reboot")
        },
        {
            id: "sc_shutdown",
            title: "Shut Down",
            subtitle: "Power off the computer",
            category: "SHORTCUTS",
            kindTag: "Power Control",
            icon: "⏻",
            glyph: "⏻",
            accentColor: "#f38ba8",
            keys: ["SHUTDOWN"],
            desc: "Safely powers off your machine.",
            actionLabel: "Power Off",
            keywords: ["shutdown", "poweroff", "turn off", "power"],
            action: () => Services.SystemService.runCmd("systemctl poweroff")
        },
        {
            id: "sc_exit",
            title: "Log Out",
            subtitle: "Exit Hyprland desktop session",
            category: "SHORTCUTS",
            kindTag: "Session Control",
            icon: "󰍃",
            glyph: "󰍃",
            accentColor: "#f38ba8",
            keys: ["SUPER", "M"],
            desc: "Exits the current Hyprland session and returns to login greeter.",
            actionLabel: "Log Out",
            keywords: ["logout", "exit", "quit session"],
            action: () => Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.exit()'")
        }
    ]

    // ── Built-in Suggested Terminal Commands ─────────
    readonly property var suggestedCommands: [
        {
            id: "cmd_btop",
            title: "btop - System Resource Monitor",
            subtitle: "Interactive CPU, memory, disk, and network stats",
            category: "COMMANDS",
            kindTag: "CLI Tool",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#a6e3a1",
            cmd: "btop",
            desc: "Full-featured modern system monitoring tool for Linux.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["btop", "top", "monitor", "cpu", "ram", "processes"],
            action: () => root.runTerminalCmd("btop", false)
        },
        {
            id: "cmd_fastfetch",
            title: "fastfetch - System Info Overview",
            subtitle: "Neofetch-style system and hardware summary",
            category: "COMMANDS",
            kindTag: "CLI Tool",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#89b4fa",
            cmd: "fastfetch",
            desc: "Displays system specs, kernel, desktop environment, and GPU info.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["fastfetch", "neofetch", "info", "specs", "hardware"],
            action: () => root.runTerminalCmd("fastfetch", true)
        },
        {
            id: "cmd_yazi",
            title: "yazi - Terminal File Manager",
            subtitle: "Fast asynchronous terminal file explorer",
            category: "COMMANDS",
            kindTag: "CLI Tool",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#fab387",
            cmd: "yazi",
            desc: "Modern terminal file manager with inline image previews and fuzzy search.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["yazi", "files", "fm", "ranger", "directory"],
            action: () => root.runTerminalCmd("yazi", false)
        },
        {
            id: "cmd_vim",
            title: "vim - Terminal Text Editor",
            subtitle: "Edit files in terminal with Vim",
            category: "COMMANDS",
            kindTag: "CLI Tool",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#a6e3a1",
            cmd: "vim",
            desc: "Powerful modal text editor for software development and configuration.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["vim", "nvim", "edit", "editor", "text"],
            action: () => root.runTerminalCmd("vim", false)
        },
        {
            id: "cmd_pacman",
            title: "pacman -Syu - System Package Update",
            subtitle: "Synchronize and update all system packages",
            category: "COMMANDS",
            kindTag: "Package Manager",
            icon: "󰮯",
            glyph: "󰮯",
            accentColor: "#89dceb",
            cmd: "sudo pacman -Syu",
            desc: "Refreshes package repositories and installs all available OS updates.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["pacman", "update", "upgrade", "syu", "packages"],
            action: () => root.runTerminalCmd("sudo pacman -Syu", false)
        },
        {
            id: "cmd_journalctl",
            title: "journalctl - System Logs",
            subtitle: "View real-time systemd service journal logs",
            category: "COMMANDS",
            kindTag: "System Logs",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#f9e2af",
            cmd: "journalctl -xe -f",
            desc: "Monitors real-time logs from kernel, desktop, and system services.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["journalctl", "logs", "systemd", "errors", "debug"],
            action: () => root.runTerminalCmd("journalctl -xe -f", false)
        },
        {
            id: "cmd_ipa",
            title: "ip a - Network Interfaces & IP Addresses",
            subtitle: "List IP addresses and network status",
            category: "COMMANDS",
            kindTag: "Network Utility",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#cba6f7",
            cmd: "ip a",
            desc: "Displays detailed network configuration for all network adapters.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["ip", "ifconfig", "network", "address", "mac"],
            action: () => root.runTerminalCmd("ip a", true)
        },
        {
            id: "cmd_ping",
            title: "ping 8.8.8.8 - Test Internet Connectivity",
            subtitle: "Send ICMP packets to Google DNS",
            category: "COMMANDS",
            kindTag: "Network Utility",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#94e2d5",
            cmd: "ping 8.8.8.8",
            desc: "Measures packet round-trip time and internet latency in milliseconds.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["ping", "latency", "dns", "internet"],
            action: () => root.runTerminalCmd("ping 8.8.8.8", false)
        },
        {
            id: "cmd_df",
            title: "df -h - Disk Space Usage",
            subtitle: "Check remaining disk capacity across partitions",
            category: "COMMANDS",
            kindTag: "Storage Utility",
            icon: "󰞷",
            glyph: "󰞷",
            accentColor: "#fab387",
            cmd: "df -h",
            desc: "Displays human-readable free and used disk space on all mounted filesystems.",
            actionLabel: "Run in " + root.terminalName,
            keywords: ["df", "disk", "storage", "space", "free"],
            action: () => root.runTerminalCmd("df -h", true)
        },
        {
            id: "cmd_hypr_reload",
            title: "hyprctl reload - Reload Hyprland",
            subtitle: "Re-parse Hyprland configuration and keybindings",
            category: "COMMANDS",
            kindTag: "Compositor",
            icon: "󰒓",
            glyph: "󰒓",
            accentColor: "#89b4fa",
            cmd: "hyprctl reload",
            desc: "Reloads Hyprland compositor settings without restarting active windows.",
            actionLabel: "Reload Hyprland",
            keywords: ["reload", "hyprland", "hyprctl"],
            action: () => root.runBgCmd("hyprctl reload")
        }
    ]

    // ── Unified Search & Categorization Engine ───────
    function updateSearchResults() {
        const rawQ = searchInput.text.trim();
        const q = rawQ.toLowerCase();
        root.searchQuery = rawQ;

        let out = [];

        // 1. Check for Math / Calculation
        const mathVal = root.evaluateMath(rawQ);
        const hasMathOps = /[+\-*/^%=]|sqrt|sin|cos|tan|pi/i.test(rawQ);
        let calcItem = null;
        if (mathVal !== "" && (hasMathOps || rawQ.startsWith("="))) {
            calcItem = {
                id: "calc_" + rawQ,
                type: "calc",
                title: "= " + mathVal,
                subtitle: "Calculation: " + rawQ,
                category: "CALCULATOR",
                kindTag: "Instant Math",
                icon: "󰃬",
                glyph: "󰃬",
                accentColor: "#a6e3a1",
                formula: rawQ,
                result: mathVal,
                desc: "Evaluated math formula. Press Enter to copy to clipboard.",
                actionLabel: "Copy Result",
                action: () => root.copyToClipboard(mathVal)
            };
        }

        // Helper: retrieve desktop entries
        const allAppsRaw = DesktopEntries.applications.values || [];
        const allApps = allAppsRaw.filter(a => a && a.name && !a.noDisplay);

        // ─────────────────────────────────────────────────────────────
        // 1. APPS TAB (Launchpad behavior with suggestions)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "apps") {
            if (q === "") {
                const suggestedNames = [root.terminalApp, root.browserApp, root.fileManagerApp, "code", "antigravity", "spotify", "discord", "steam", "obs"];
                const suggestedApps = [];
                const otherApps = [];

                for (let i = 0; i < allApps.length; i++) {
                    const a = allApps[i];
                    const n = (a.name || "").toLowerCase();
                    const id = (a.id || "").toLowerCase();
                    const isSuggested = suggestedNames.some(s => s && (n.includes(s) || id.includes(s)));
                    if (isSuggested && suggestedApps.length < 5) {
                        suggestedApps.push(a);
                    } else {
                        otherApps.push(a);
                    }
                }

                // Suggestions Section
                for (let i = 0; i < suggestedApps.length; i++) {
                    const app = suggestedApps[i];
                    out.push({
                        id: "app_sug_" + (app.id || app.name),
                        type: "app",
                        title: app.name ?? "Application",
                        subtitle: app.genericName || app.comment || "Suggested Application",
                        category: "SUGGESTIONS",
                        kindTag: "Suggested",
                        icon: app.icon ?? "",
                        glyph: "󰣆",
                        accentColor: root.theme.accent,
                        entry: app,
                        exec: app.id || app.name,
                        desc: app.comment || app.genericName || "Desktop Application",
                        actionLabel: "Launch Application",
                        action: () => { app.execute(); closeLauncher(); }
                    });
                }

                // Applications Section (A-Z)
                otherApps.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
                for (let i = 0; i < otherApps.length; i++) {
                    const app = otherApps[i];
                    out.push({
                        id: "app_other_" + (app.id || app.name),
                        type: "app",
                        title: app.name ?? "Application",
                        subtitle: app.genericName || app.comment || "Application",
                        category: "APPLICATIONS",
                        kindTag: "Application",
                        icon: app.icon ?? "",
                        glyph: "󰣆",
                        accentColor: root.theme.accent,
                        entry: app,
                        exec: app.id || app.name,
                        desc: app.comment || app.genericName || "Desktop Application",
                        actionLabel: "Launch Application",
                        action: () => { app.execute(); closeLauncher(); }
                    });
                }

                root.results = out;
                root.selectedIndex = 0;
                return;
            }

            // Query in Apps tab
            // 1. Math calculation support
            if (calcItem) {
                out.push(calcItem);
            }

            // 2. Command prefix '>' support
            if (rawQ.startsWith(">")) {
                const cmdStr = rawQ.substring(1).trim();
                if (cmdStr) {
                    out.push({
                        id: "cmd_custom_term",
                        type: "cmd",
                        title: "Run: " + cmdStr,
                        subtitle: "Execute command in " + root.terminalName + " terminal",
                        category: "TERMINAL EXECUTION",
                        kindTag: "Terminal Command",
                        icon: "󰞷",
                        glyph: "󰞷",
                        accentColor: root.theme.accent,
                        cmd: cmdStr,
                        desc: "Runs '" + cmdStr + "' directly in " + root.terminalName + " terminal session.",
                        actionLabel: "Run in " + root.terminalName,
                        action: () => root.runTerminalCmd(cmdStr, false)
                    });
                    root.results = out;
                    root.selectedIndex = 0;
                    return;
                }
            }

            const filtered = allApps.filter(app => {
                const n = (app.name ?? "").toLowerCase();
                const gen = (app.genericName ?? "").toLowerCase();
                const com = (app.comment ?? "").toLowerCase();
                const exec = (app.id ?? "").toLowerCase();
                return n.includes(q) || gen.includes(q) || com.includes(q) || exec.includes(q);
            }).sort((a, b) => {
                const an = (a.name ?? "").toLowerCase();
                const bn = (b.name ?? "").toLowerCase();
                const aStarts = an.startsWith(q);
                const bStarts = bn.startsWith(q);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return an.localeCompare(bn);
            });

            for (let i = 0; i < filtered.length; i++) {
                const app = filtered[i];
                out.push({
                    id: "app_res_" + (app.id || app.name) + "_" + i,
                    type: "app",
                    title: app.name ?? "Application",
                    subtitle: app.genericName || app.comment || "Application",
                    category: i === 0 ? "TOP HIT" : "APPLICATIONS",
                    kindTag: "Application",
                    icon: app.icon ?? "",
                    glyph: "󰣆",
                    accentColor: root.theme.accent,
                    entry: app,
                    exec: app.id || app.name,
                    desc: app.comment || app.genericName || "Desktop Application",
                    actionLabel: "Open Application",
                    action: () => { app.execute(); closeLauncher(); }
                });
            }

            if (out.length === 0) {
                out.push(root.makeWebSearchItem(rawQ));
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 2. WINDOWS TAB (Hyprland Active Window Switcher)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "windows") {
            const wins = root.hyprWindows || [];
            let matchedWins = [];

            if (q === "") {
                matchedWins = wins;
            } else {
                matchedWins = wins.filter(w => {
                    const t = (w.title || "").toLowerCase();
                    const c = (w.clazz || "").toLowerCase();
                    const ws = (w.workspaceName || "").toLowerCase();
                    return t.includes(q) || c.includes(q) || ws.includes(q);
                });
            }

            if (matchedWins.length === 0) {
                out.push({
                    id: "win_empty",
                    type: "info",
                    title: q === "" ? "No active windows found" : "No windows matching \"" + rawQ + "\"",
                    subtitle: "Open applications across your workspaces will appear here",
                    category: "OPEN WINDOWS",
                    kindTag: "Window Switcher",
                    icon: "",
                    glyph: "󰖲",
                    accentColor: root.theme.textMuted,
                    desc: "Switch between open windows across all workspaces with instantaneous focus.",
                    actionLabel: "No Window",
                    action: () => {}
                });
            } else {
                for (let i = 0; i < matchedWins.length; i++) {
                    const w = matchedWins[i];
                    out.push(root.makeWindowResultItem(w, i === 0 && q !== "" ? "TOP HIT" : "OPEN WINDOWS (" + matchedWins.length + ")"));
                }
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 3. COMMANDS TAB (CLI Tools & Terminal Runner)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "commands") {
            if (q === "") {
                for (let i = 0; i < root.suggestedCommands.length; i++) {
                    const cmd = root.suggestedCommands[i];
                    out.push(Object.assign({}, cmd, {
                        category: "SUGGESTED COMMANDS"
                    }));
                }
            } else {
                const cleanQ = rawQ.startsWith(">") ? rawQ.substring(1).trim() : rawQ;

                out.push({
                    id: "cmd_custom_term",
                    type: "cmd",
                    title: "Run: " + cleanQ,
                    subtitle: "Execute command in " + root.terminalName + " terminal",
                    category: "TERMINAL EXECUTION",
                    kindTag: "Terminal Command",
                    icon: "󰞷",
                    glyph: "󰞷",
                    accentColor: root.theme.accent,
                    cmd: cleanQ,
                    desc: "Runs '" + cleanQ + "' directly in " + root.terminalName + " terminal session.",
                    actionLabel: "Run in " + root.terminalName,
                    action: () => root.runTerminalCmd(cleanQ, false)
                });

                out.push({
                    id: "cmd_custom_bg",
                    type: "cmd",
                    title: "Run in Background: " + cleanQ,
                    subtitle: "Spawn command silently without terminal",
                    category: "BACKGROUND EXECUTION",
                    kindTag: "Background Command",
                    icon: "󰜎",
                    glyph: "󰜎",
                    accentColor: root.theme.textMuted,
                    cmd: cleanQ,
                    desc: "Executes '" + cleanQ + "' silently in background.",
                    actionLabel: "Run in Background",
                    action: () => root.runBgCmd(cleanQ)
                });

                for (let i = 0; i < root.suggestedCommands.length; i++) {
                    const cmd = root.suggestedCommands[i];
                    const tMatch = cmd.title.toLowerCase().includes(q);
                    const cMatch = cmd.cmd.toLowerCase().includes(q);
                    const kMatch = cmd.keywords.some(k => k.includes(q));
                    if (tMatch || cMatch || kMatch) {
                        out.push(Object.assign({}, cmd, {
                            category: "MATCHED COMMANDS"
                        }));
                    }
                }
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 4. SHORTCUTS TAB (System Controls & Keybindings)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "shortcuts") {
            if (q === "") {
                for (let i = 0; i < root.systemShortcuts.length; i++) {
                    const sc = root.systemShortcuts[i];
                    out.push(Object.assign({}, sc, {
                        category: "SYSTEM SHORTCUTS"
                    }));
                }
            } else {
                for (let i = 0; i < root.systemShortcuts.length; i++) {
                    const sc = root.systemShortcuts[i];
                    const tMatch = sc.title.toLowerCase().includes(q);
                    const sMatch = sc.subtitle.toLowerCase().includes(q);
                    const kMatch = sc.keywords.some(k => k.includes(q));
                    if (tMatch || sMatch || kMatch) {
                        out.push(Object.assign({}, sc, {
                            category: out.length === 0 ? "TOP HIT" : "SHORTCUTS"
                        }));
                    }
                }
                if (out.length === 0) {
                    out.push(root.makeWebSearchItem(rawQ));
                }
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 5. MATH TAB (Calculator & Instant Expressions)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "math") {
            if (calcItem) {
                out.push(calcItem);
            } else if (q !== "") {
                out.push({
                    id: "calc_incomplete",
                    type: "calc_help",
                    title: "Calculating: " + rawQ,
                    subtitle: "Supports +, -, *, /, ^, %, sqrt(), sin(), cos(), tan(), pi",
                    category: "CALCULATOR",
                    kindTag: "Math Input",
                    icon: "󰃬",
                    glyph: "󰃬",
                    accentColor: root.theme.accent,
                    desc: "Enter a mathematical expression like '15% of 850', 'sqrt(144)', or '2^8'.",
                    actionLabel: "Calculate",
                    action: () => {}
                });
            }

            const examples = [
                { expr: "15% of 850", result: "127.5" },
                { expr: "sqrt(144) + 25", result: "37" },
                { expr: "2 ^ 10", result: "1024" },
                { expr: "128 * 4.5", result: "576" },
                { expr: "sin(45) * 100", result: "70.71" },
                { expr: "pi * 10^2", result: "314.159265" }
            ];

            for (let i = 0; i < examples.length; i++) {
                const ex = examples[i];
                out.push({
                    id: "calc_ex_" + i,
                    type: "calc_ex",
                    title: ex.expr + "  =  " + ex.result,
                    subtitle: "Example calculation",
                    category: "EXAMPLE EXPRESSIONS",
                    kindTag: "Example",
                    icon: "󰃬",
                    glyph: "󰃬",
                    accentColor: "#fab387",
                    formula: ex.expr,
                    result: ex.result,
                    desc: "Click or press Enter to populate search input with '" + ex.expr + "'.",
                    actionLabel: "Try Expression",
                    action: () => {
                        searchInput.text = ex.expr;
                        searchInput.forceActiveFocus();
                    }
                });
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ─────────────────────────────────────────────────────────────
        // 6. ALL TAB (Unified Cross-Category Search)
        // ─────────────────────────────────────────────────────────────
        if (root.activeCategory === "all") {
            if (q === "") {
                const topApps = allApps.filter(a => {
                    const n = (a.name ?? "").toLowerCase();
                    const id = (a.id ?? "").toLowerCase();
                    return (root.terminalApp && (n.includes(root.terminalApp) || id.includes(root.terminalApp))) ||
                           (root.browserApp && (n.includes(root.browserApp) || id.includes(root.browserApp))) ||
                           (root.fileManagerApp && (n.includes(root.fileManagerApp) || id.includes(root.fileManagerApp))) ||
                           n.includes("code");
                }).slice(0, 3);

                for (let i = 0; i < topApps.length; i++) {
                    const app = topApps[i];
                    out.push({
                        id: "app_all_" + (app.id || app.name),
                        type: "app",
                        title: app.name ?? "Application",
                        subtitle: app.genericName || app.comment || "Application",
                        category: "APPLICATIONS",
                        kindTag: "Application",
                        icon: app.icon ?? "",
                        glyph: "󰣆",
                        accentColor: root.theme.accent,
                        entry: app,
                        exec: app.id || app.name,
                        desc: app.comment || app.genericName || "Desktop Application",
                        actionLabel: "Open Application",
                        action: () => { app.execute(); closeLauncher(); }
                    });
                }

                const wins = root.hyprWindows || [];
                for (let i = 0; i < Math.min(3, wins.length); i++) {
                    out.push(root.makeWindowResultItem(wins[i], "OPEN WINDOWS"));
                }

                const topSc = [root.systemShortcuts[0], root.systemShortcuts[1], root.systemShortcuts[2]];
                for (let i = 0; i < topSc.length; i++) {
                    if (topSc[i]) out.push(topSc[i]);
                }

                const topCmd = [root.suggestedCommands[0], root.suggestedCommands[1]];
                for (let i = 0; i < topCmd.length; i++) {
                    if (topCmd[i]) out.push(topCmd[i]);
                }

                root.results = out;
                root.selectedIndex = 0;
                return;
            }

            let matchedCalc = calcItem;
            let matchedApps = [];
            let matchedWins = [];
            let matchedShortcuts = [];
            let matchedCommands = [];

            if (rawQ.startsWith(">")) {
                const cmdStr = rawQ.substring(1).trim();
                if (cmdStr) {
                    out.push({
                        id: "custom_cmd_" + cmdStr,
                        type: "cmd",
                        title: "Run: " + cmdStr,
                        subtitle: "Execute in " + root.terminalName + " terminal",
                        category: "TOP HIT",
                        kindTag: "Terminal Command",
                        icon: "󰞷",
                        glyph: "󰞷",
                        accentColor: root.theme.accent,
                        cmd: cmdStr,
                        desc: "Runs '" + cmdStr + "' directly in " + root.terminalName + " terminal.",
                        actionLabel: "Run in " + root.terminalName,
                        action: () => root.runTerminalCmd(cmdStr, false)
                    });
                    out.push({
                        id: "custom_bg_" + cmdStr,
                        type: "cmd",
                        title: "Run in Background: " + cmdStr,
                        subtitle: "Execute silently in background",
                        category: "COMMANDS",
                        kindTag: "Background Command",
                        icon: "󰜎",
                        glyph: "󰜎",
                        accentColor: root.theme.textMuted,
                        cmd: cmdStr,
                        desc: "Spawns '" + cmdStr + "' silently without a terminal window.",
                        actionLabel: "Run in Background",
                        action: () => root.runBgCmd(cmdStr)
                    });
                    root.results = out;
                    root.selectedIndex = 0;
                    return;
                }
            }

            // Open windows match
            const wins = root.hyprWindows || [];
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i];
                const t = (w.title || "").toLowerCase();
                const c = (w.clazz || "").toLowerCase();
                if (t.includes(q) || c.includes(q)) {
                    matchedWins.push(root.makeWindowResultItem(w, "OPEN WINDOWS"));
                }
            }

            // Desktop apps match
            const appMatches = allApps.filter(app => {
                const n = (app.name ?? "").toLowerCase();
                const gen = (app.genericName ?? "").toLowerCase();
                const com = (app.comment ?? "").toLowerCase();
                return n.includes(q) || gen.includes(q) || com.includes(q);
            }).sort((a, b) => {
                const an = (a.name ?? "").toLowerCase();
                const bn = (b.name ?? "").toLowerCase();
                const aStarts = an.startsWith(q);
                const bStarts = bn.startsWith(q);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return an.localeCompare(bn);
            });

            for (let i = 0; i < Math.min(6, appMatches.length); i++) {
                const app = appMatches[i];
                matchedApps.push({
                    id: "app_" + (app.id || app.name),
                    type: "app",
                    title: app.name ?? "Application",
                    subtitle: app.genericName || app.comment || "Application",
                    category: "APPLICATIONS",
                    kindTag: "Application",
                    icon: app.icon ?? "",
                    glyph: "󰣆",
                    accentColor: root.theme.accent,
                    entry: app,
                    exec: app.id || app.name,
                    desc: app.comment || app.genericName || "Desktop Application",
                    actionLabel: "Open Application",
                    action: () => { app.execute(); closeLauncher(); }
                });
            }

            // Shortcuts match
            for (let i = 0; i < root.systemShortcuts.length; i++) {
                const sc = root.systemShortcuts[i];
                const tMatch = sc.title.toLowerCase().includes(q);
                const sMatch = sc.subtitle.toLowerCase().includes(q);
                const kMatch = sc.keywords.some(k => k.includes(q));
                if (tMatch || sMatch || kMatch) matchedShortcuts.push(sc);
            }

            // Commands match
            for (let i = 0; i < root.suggestedCommands.length; i++) {
                const cmd = root.suggestedCommands[i];
                const tMatch = cmd.title.toLowerCase().includes(q);
                const cMatch = cmd.cmd.toLowerCase().includes(q);
                const kMatch = cmd.keywords.some(k => k.includes(q));
                if (tMatch || cMatch || kMatch) matchedCommands.push(cmd);
            }

            // Determine TOP HIT
            let topHit = null;
            if (matchedCalc && (rawQ.startsWith("=") || /^[0-9+\-*/().%^ eE]+$/.test(rawQ))) {
                topHit = matchedCalc;
                matchedCalc = null;
            } else if (matchedApps.length > 0 && matchedApps[0].title.toLowerCase().startsWith(q)) {
                topHit = matchedApps.shift();
            } else if (matchedWins.length > 0 && matchedWins[0].title.toLowerCase().startsWith(q)) {
                topHit = matchedWins.shift();
            } else if (matchedShortcuts.length > 0 && matchedShortcuts[0].title.toLowerCase().startsWith(q)) {
                topHit = matchedShortcuts.shift();
            } else if (matchedCommands.length > 0 && matchedCommands[0].cmd.toLowerCase().startsWith(q)) {
                topHit = matchedCommands.shift();
            } else if (matchedApps.length > 0) {
                topHit = matchedApps.shift();
            } else if (matchedWins.length > 0) {
                topHit = matchedWins.shift();
            } else if (matchedShortcuts.length > 0) {
                topHit = matchedShortcuts.shift();
            } else if (matchedCommands.length > 0) {
                topHit = matchedCommands.shift();
            } else if (matchedCalc) {
                topHit = matchedCalc;
                matchedCalc = null;
            }

            if (topHit) {
                topHit.category = "TOP HIT";
                out.push(topHit);
            }

            for (let i = 0; i < matchedApps.length; i++) {
                matchedApps[i].category = "APPLICATIONS";
                out.push(matchedApps[i]);
            }
            for (let i = 0; i < matchedWins.length; i++) {
                matchedWins[i].category = "OPEN WINDOWS";
                out.push(matchedWins[i]);
            }
            for (let i = 0; i < matchedShortcuts.length; i++) {
                matchedShortcuts[i].category = "SHORTCUTS";
                out.push(matchedShortcuts[i]);
            }
            for (let i = 0; i < matchedCommands.length; i++) {
                matchedCommands[i].category = "COMMANDS";
                out.push(matchedCommands[i]);
            }

            if (rawQ.length > 1 && !topHit && matchedApps.length === 0 && matchedWins.length === 0) {
                out.push({
                    id: "typed_cmd_" + rawQ,
                    type: "cmd",
                    title: "Run: " + rawQ,
                    subtitle: "Execute terminal command in " + root.terminalName,
                    category: "COMMANDS",
                    kindTag: "Terminal Command",
                    icon: "󰞷",
                    glyph: "󰞷",
                    accentColor: root.theme.accent,
                    cmd: rawQ,
                    desc: "Runs '" + rawQ + "' directly in " + root.terminalName + " terminal.",
                    actionLabel: "Run in " + root.terminalName,
                    action: () => root.runTerminalCmd(rawQ, false)
                });
            }

            out.push(root.makeWebSearchItem(rawQ));

            root.results = out;
            root.selectedIndex = 0;
            return;
        }
    }

    // ── Execute Active Selected Result ───────────────
    readonly property var selectedItem: (results.length > 0 && selectedIndex >= 0 && selectedIndex < results.length) ? results[selectedIndex] : null

    function executeSelectedItem() {
        if (!selectedItem) {
            const q = searchInput.text.trim();
            if (q) searchWeb(q);
            return;
        }
        closeLauncher();
        if (selectedItem.action) {
            selectedItem.action();
        }
    }

    Component.onCompleted: {
        root.fetchWindows();
    }

    // ── Full-Screen Overlay Window ───────────────────
    PanelWindow {
        id: launcherPanel
        visible: false
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: launcherPanel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-spotlight"
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Click outside to dismiss (transparent backdrop so Hyprland ignore_alpha rounds blur perfectly)
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeLauncher()
        }

        // ── Spotlight Floating Card (macOS Tahoe & Raycast Scopes) ──────
        Rectangle {
            id: spotlightBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.15

            width: 740
            height: 520
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

            Behavior on height {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            // Top specular highlight line (macOS glass edge)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Services.Aesthetic.cardRadius
                anchors.rightMargin: Services.Aesthetic.cardRadius
                height: 1
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // Stop click through
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ── 1. SPOTLIGHT SEARCH INPUT ROW ────
                Rectangle {
                    Layout.fillWidth: true
                    height: 54
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12

                        // Magnifying glass icon
                        Text {
                            text: "󰍉"
                            color: root.theme.textMuted
                            font.pixelSize: 22
                            font.family: root.font
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Seamless search input field
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            color: root.theme.textPrimary
                            font.pixelSize: 17
                            font.family: root.font
                            font.weight: Font.Normal
                            clip: true
                            focus: true

                            Text {
                                anchors.fill: parent
                                text: root.searchPlaceholder
                                color: root.theme.textMuted
                                font: parent.font
                                visible: !parent.text
                                verticalAlignment: Text.AlignVCenter
                            }

                            onTextChanged: {
                                root.selectedIndex = 0;
                                root.updateSearchResults();
                            }

                            Keys.onEscapePressed: {
                                if (text !== "") {
                                    text = "";
                                } else {
                                    root.closeLauncher();
                                }
                            }

                            Keys.onPressed: (event) => {
                                // 1. Tab / Shift+Tab cycles Category Filter Chips
                                if ((event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
                                    event.accepted = true;
                                    root.cycleCategory(-1);
                                    return;
                                } else if (event.key === Qt.Key_Tab) {
                                    event.accepted = true;
                                    root.cycleCategory(1);
                                    return;
                                }

                                // 2. Up/Down navigation (also Ctrl+J / Ctrl+K)
                                if (event.key === Qt.Key_Down || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_J)) {
                                    event.accepted = true;
                                    if (root.results.length > 0) {
                                        root.selectedIndex = (root.selectedIndex + 1) % root.results.length;
                                        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    }
                                    return;
                                } else if (event.key === Qt.Key_Up || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K)) {
                                    event.accepted = true;
                                    if (root.results.length > 0) {
                                        root.selectedIndex = (root.selectedIndex - 1 + root.results.length) % root.results.length;
                                        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    }
                                    return;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;
                                    root.executeSelectedItem();
                                    return;
                                }

                                // 3. Secondary Actions Shortcuts (Raycast-style)
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_W) {
                                    if (root.selectedItem && root.selectedItem.type === "window") {
                                        event.accepted = true;
                                        root.closeWindow(root.selectedItem.address);
                                        return;
                                    }
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                                    if (root.selectedItem && root.selectedItem.type === "window") {
                                        event.accepted = true;
                                        root.toggleWindowFloat(root.selectedItem.address);
                                        return;
                                    }
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_B) {
                                    if (root.selectedItem && (root.selectedItem.type === "cmd" || root.selectedItem.cmd)) {
                                        event.accepted = true;
                                        root.runBgCmd(root.selectedItem.cmd);
                                        return;
                                    }
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                                    // If no text selected inside input field, copy selected item's text!
                                    if (searchInput.selectedText === "" && root.selectedItem) {
                                        event.accepted = true;
                                        const cpText = root.selectedItem.result || root.selectedItem.cmd || root.selectedItem.title || "";
                                        if (cpText) root.copyToClipboard(cpText);
                                        return;
                                    }
                                }
                            }
                        }

                        // Clear "×" button if query present
                        Rectangle {
                            visible: searchInput.text !== ""
                            width: 20
                            height: 20
                            radius: 10
                            color: clrMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: root.theme.textMuted
                                font.pixelSize: 14
                                font.family: root.font
                            }

                            MouseArea {
                                id: clrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }

                        // "esc" hint pill
                        Rectangle {
                            width: 32
                            height: 20
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "esc"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                            }
                        }
                    }
                }

                // ── 2. DIVIDER ───────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── 3. INTERACTIVE CATEGORY FILTER CHIPS ROW ────
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    color: Qt.rgba(0, 0, 0, 0.12)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 6

                        Repeater {
                            model: root.categoryList

                            Rectangle {
                                id: chipBox
                                height: 26
                                Layout.alignment: Qt.AlignVCenter
                                width: chipRow.implicitWidth + 18
                                radius: 13

                                readonly property bool isActive: root.activeCategory === modelData.id
                                readonly property bool isHovered: chipMouse.containsMouse

                                color: isActive 
                                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)
                                    : (isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                                border.color: isActive
                                    ? root.theme.accent
                                    : (isHovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        text: modelData.icon
                                        color: chipBox.isActive ? root.theme.accent : (chipBox.isHovered ? root.theme.textPrimary : root.theme.textMuted)
                                        font.pixelSize: 11
                                        font.family: root.font
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        text: modelData.label
                                        color: chipBox.isActive ? root.theme.accent : (chipBox.isHovered ? root.theme.textPrimary : root.theme.textMuted)
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: chipBox.isActive ? Font.DemiBold : Font.Normal
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeCategory = modelData.id;
                                        root.selectedIndex = 0;
                                        root.updateSearchResults();
                                        searchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Keyboard Tab switch hint
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            opacity: 0.65

                            Rectangle {
                                height: 16
                                width: tabHint.implicitWidth + 6
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.08)
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: tabHint
                                    anchors.centerIn: parent
                                    text: "Tab"
                                    color: root.theme.textMuted
                                    font.pixelSize: 9
                                    font.family: root.font
                                }
                            }

                            Text {
                                text: "to filter"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                // ── 4. DIVIDER ───────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── 5. DUAL-PANE CONTENT ─────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // ── LEFT PANE: RESULTS LIST (width: 430px) ──
                    Rectangle {
                        Layout.preferredWidth: 430
                        Layout.fillHeight: true
                        color: "transparent"
                        clip: true

                        ListView {
                            id: resultsList
                            anchors.fill: parent
                            anchors.margins: 8
                            model: root.results
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            currentIndex: root.selectedIndex

                            delegate: Column {
                                width: resultsList.width

                                // Categorical Section Header
                                Item {
                                    width: parent.width
                                    height: 22
                                    visible: index === 0 || resultsList.model[index].category !== resultsList.model[index - 1].category

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                        text: modelData.category
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                    }
                                }

                                // Interactive Result Item
                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    radius: 8
                                    color: root.selectedIndex === index ? root.theme.accent : (itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

                                    Behavior on color { ColorAnimation { duration: 80 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        // Icon Container
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.08)

                                            IconImage {
                                                anchors.centerIn: parent
                                                width: 20
                                                height: 20
                                                source: Quickshell.iconPath(modelData.icon ?? "", true)
                                                visible: (modelData.type === "app" || modelData.type === "window") && (modelData.icon ?? "") !== ""
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.glyph ?? (modelData.icon ?? "󰣆")
                                                color: root.selectedIndex === index ? "#ffffff" : (modelData.accentColor ?? root.theme.accent)
                                                font.pixelSize: 14
                                                font.family: root.font
                                                visible: (modelData.type !== "app" && modelData.type !== "window") || (modelData.icon ?? "") === ""
                                            }
                                        }

                                        // Title
                                        Text {
                                            text: modelData.title ?? ""
                                            color: root.selectedIndex === index ? "#ffffff" : root.theme.textPrimary
                                            font.pixelSize: 13
                                            font.family: root.font
                                            font.weight: root.selectedIndex === index ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Subtitle Tag / Badge on the right
                                        Rectangle {
                                            height: 18
                                            width: tagTxt.implicitWidth + 8
                                            radius: 4
                                            color: root.selectedIndex === index ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.06)

                                            Text {
                                                id: tagTxt
                                                anchors.centerIn: parent
                                                text: modelData.category === "TOP HIT" ? "Top Hit" : (modelData.kindTag ?? modelData.category)
                                                color: root.selectedIndex === index ? "#ffffff" : root.theme.textMuted
                                                font.pixelSize: 9
                                                font.family: root.font
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.selectedIndex = index
                                        onClicked: {
                                            root.selectedIndex = index;
                                            root.executeSelectedItem();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── VERTICAL DIVIDER ─────────────────
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // ── RIGHT PANE: SPOTLIGHT PREVIEW PANE ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "transparent"
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            // ── TOP: Icon + Large Title + Kind ──
                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                spacing: 8

                                // Large 56x56 Squircle Icon
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 56
                                    height: 56
                                    radius: 13
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 42
                                        height: 42
                                        source: Quickshell.iconPath(root.selectedItem?.icon ?? "", true)
                                        visible: (root.selectedItem?.type === "app" || root.selectedItem?.type === "window") && (root.selectedItem?.icon ?? "") !== ""
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.selectedItem?.glyph ?? (root.selectedItem?.icon ?? "󰣆")
                                        color: root.selectedItem?.accentColor ?? root.theme.accent
                                        font.pixelSize: 28
                                        font.family: root.font
                                        visible: (root.selectedItem?.type !== "app" && root.selectedItem?.type !== "window") || (root.selectedItem?.icon ?? "") === ""
                                    }
                                }

                                // Large Title
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 260
                                    text: root.selectedItem?.title ?? "Spotlight Search"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 14
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                // Kind Tag
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedItem?.kindTag ?? (root.selectedItem?.category ?? "")
                                    color: root.theme.textMuted
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            // Divider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.07)
                            }

                            // ── MIDDLE: Rich Contextual Details ──

                            // 1. Math Evaluation Display
                            ColumnLayout {
                                visible: root.selectedItem?.type === "calc"
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedItem?.formula ?? ""
                                    color: root.theme.textMuted
                                    font.pixelSize: 12
                                    font.family: root.font
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "= " + (root.selectedItem?.result ?? "")
                                    color: root.theme.accentGreen
                                    font.pixelSize: 24
                                    font.family: root.font
                                    font.weight: Font.Bold
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Press ↵ to copy answer to clipboard"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                }
                            }

                            // 2. Open Window Metadata (for Window Switcher)
                            ColumnLayout {
                                visible: root.selectedItem?.type === "window"
                                Layout.fillWidth: true
                                spacing: 7

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "App:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.selectedItem?.clazz ?? ""; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font; font.weight: Font.DemiBold }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Workspace:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.selectedItem?.wsName ?? ""; color: root.theme.accent; font.pixelSize: 10; font.family: root.font; font.weight: Font.Bold }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "State:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.selectedItem?.floating ? "Floating" : "Tiled"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Address:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.selectedItem?.address ?? ""; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font }
                                }
                            }

                            // 3. Standard Metadata Rows (Apps, Shortcuts, Commands)
                            ColumnLayout {
                                visible: root.selectedItem?.type !== "calc" && root.selectedItem?.type !== "window"
                                Layout.fillWidth: true
                                spacing: 7

                                // Keybinding pills (for shortcuts)
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: !!root.selectedItem?.keys && root.selectedItem.keys.length > 0

                                    Text {
                                        text: "Shortcut:"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }

                                    Item { Layout.fillWidth: true }

                                    Row {
                                        spacing: 4
                                        Repeater {
                                            model: root.selectedItem?.keys ?? []
                                            Rectangle {
                                                height: 18
                                                width: keyCapTxt.implicitWidth + 8
                                                radius: 4
                                                color: Qt.rgba(1, 1, 1, 0.1)
                                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                                border.width: 1

                                                Text {
                                                    id: keyCapTxt
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 9
                                                    font.family: root.font
                                                    font.weight: Font.Bold
                                                }
                                            }
                                        }
                                    }
                                }

                                // Command row (for terminal commands)
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: !!root.selectedItem?.cmd

                                    Text {
                                        text: "Command:"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        height: 18
                                        width: cmdTxt.implicitWidth + 8
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)

                                        Text {
                                            id: cmdTxt
                                            anchors.centerIn: parent
                                            text: root.selectedItem?.cmd ?? ""
                                            color: root.theme.accent
                                            font.pixelSize: 9
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                // Executable row (for desktop apps)
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.selectedItem?.type === "app" && !!root.selectedItem?.exec

                                    Text {
                                        text: "Executable:"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.selectedItem?.exec ?? ""
                                        color: root.theme.textPrimary
                                        font.pixelSize: 10
                                        font.family: root.font
                                        font.weight: Font.Medium
                                        elide: Text.ElideLeft
                                        Layout.maximumWidth: 160
                                    }
                                }

                                // Description
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: !!root.selectedItem?.desc
                                    spacing: 3

                                    Text {
                                        text: "Description:"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }

                                    Text {
                                        text: root.selectedItem?.desc ?? ""
                                        color: root.theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: root.font
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // ── SECONDARY ACTIONS BAR (Raycast-style) ──
                            // For Windows: Close / Float
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.selectedItem?.type === "window"
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: btnCloseMouse.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: btnCloseMouse.containsMouse ? "#f38ba8" : Qt.rgba(1, 1, 1, 0.1)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { text: "⌃W"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font; font.weight: Font.Bold }
                                        Text { text: "Close"; color: btnCloseMouse.containsMouse ? "#f38ba8" : root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: btnCloseMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.closeWindow(root.selectedItem.address)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: btnFloatMouse.containsMouse ? Qt.rgba(0.5, 0.8, 1, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: btnFloatMouse.containsMouse ? "#89b4fa" : Qt.rgba(1, 1, 1, 0.1)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { text: "⌃F"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font; font.weight: Font.Bold }
                                        Text { text: root.selectedItem?.floating ? "Tile" : "Float"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: btnFloatMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleWindowFloat(root.selectedItem.address)
                                    }
                                }
                            }

                            // For Commands: Background / Copy
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.selectedItem?.type === "cmd" || (!!root.selectedItem?.cmd && root.selectedItem?.type !== "window")
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: btnBgMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.1)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { text: "⌃B"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font; font.weight: Font.Bold }
                                        Text { text: "Background"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: btnBgMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runBgCmd(root.selectedItem.cmd)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: btnCpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.1)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text { text: "⌃C"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font; font.weight: Font.Bold }
                                        Text { text: "Copy"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: btnCpMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyToClipboard(root.selectedItem.cmd)
                                    }
                                }
                            }

                            // ── BOTTOM: Primary Action Button (macOS / Raycast 1:1) ──
                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 8
                                color: actMouse.pressed ? Qt.darker(root.theme.accent, 1.2) : (actMouse.containsMouse ? Qt.lighter(root.theme.accent, 1.1) : root.theme.accent)
                                scale: actMouse.pressed ? 0.98 : 1.0
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: root.selectedItem?.actionLabel ?? "Open"
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "↵"
                                        color: Qt.rgba(1, 1, 1, 0.8)
                                        font.pixelSize: 13
                                        font.family: root.font
                                    }
                                }

                                MouseArea {
                                    id: actMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.executeSelectedItem()
                                }
                            }
                        }
                    }
                }

                // ── 6. DIVIDER ───────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── 7. SPOTLIGHT FOOTER BAR ──────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16

                        Row {
                            spacing: 12

                            Row {
                                spacing: 4
                                Text { text: "↑↓"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                Text { text: "Navigate"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }

                            Row {
                                spacing: 4
                                Text { text: "↵"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font }
                                Text { text: "Select"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }

                            Row {
                                spacing: 4
                                Text { text: "Tab"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font }
                                Text { text: "Filter"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }

                            Row {
                                visible: root.selectedItem?.type === "window"
                                spacing: 4
                                Text { text: "⌃W"; color: root.theme.textMuted; font.pixelSize: 9; font.family: root.font }
                                Text { text: "Close"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }

                            Row {
                                spacing: 4
                                Text { text: "esc"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                Text { text: "Dismiss"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.results.length + " results"
                            color: root.theme.textMuted
                            font.pixelSize: 10
                            font.family: root.font
                        }
                    }
                }
            }
        }
    }
}
