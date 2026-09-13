import Quickshell
import Quickshell.Io
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

    // ── IPC Handler for External Toggle ─────────────
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcherPanel.visible = !launcherPanel.visible;
            if (launcherPanel.visible) {
                searchInput.text = "";
                root.selectedIndex = 0;
                root.updateSearchResults();
                searchInput.forceActiveFocus();
            }
        }

        function open(): void {
            launcherPanel.visible = true;
            searchInput.text = "";
            root.selectedIndex = 0;
            root.updateSearchResults();
            searchInput.forceActiveFocus();
        }

        function query(text: string): void {
            launcherPanel.visible = true;
            searchInput.text = text || "";
            root.selectedIndex = 0;
            root.updateSearchResults();
            searchInput.forceActiveFocus();
        }

        function close(): void {
            launcherPanel.visible = false;
        }
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
        const clean = cmd.replace(/^>/, '').trim();
        if (!clean) return;
        const flag = hold ? "--hold -e " : "-e ";
        Services.SystemService.runCmd("kitty --directory /home/aran " + flag + clean);
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
        Services.SystemService.runCmd("xdg-open 'https://www.google.com/search?q=" + q + "' || firefox 'https://www.google.com/search?q=" + q + "'");
        closeLauncher();
    }

    function openUrl(url) {
        let target = url.trim();
        if (!target.startsWith("http://") && !target.startsWith("https://")) {
            target = "https://" + target;
        }
        Services.SystemService.runCmd("xdg-open '" + target + "' || firefox '" + target + "'");
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
            action: () => Services.SystemService.runCmd("hyprctl dispatch togglefloating")
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
            action: () => Services.SystemService.runCmd("hyprctl dispatch fullscreen 1")
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
            action: () => Services.SystemService.runCmd("hyprctl dispatch killactive")
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
            actionLabel: "Run in Kitty",
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
                kindTag: "Calculation Result",
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

        // ── EMPTY STATE: Curated Recents & Suggestions ──
        if (q === "") {
            const allApps = [...(DesktopEntries.applications.values || [])];
            
            // Priority apps: Kitty, Firefox, Dolphin, Code
            const topApps = allApps.filter(a => {
                const n = (a.name ?? "").toLowerCase();
                const id = (a.id ?? "").toLowerCase();
                return n.includes("kitty") || n.includes("firefox") || n.includes("dolphin") || n.includes("code") || id.includes("antigravity");
            }).slice(0, 4);

            let first = true;
            for (let i = 0; i < topApps.length; i++) {
                const app = topApps[i];
                out.push({
                    id: "app_" + (app.id || app.name),
                    type: "app",
                    title: app.name ?? "Application",
                    subtitle: app.genericName || app.comment || "Application",
                    category: first ? "TOP HIT" : "APPLICATIONS",
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
                first = false;
            }

            // Suggested Top Shortcuts
            const topShortcuts = [root.systemShortcuts[0], root.systemShortcuts[1], root.systemShortcuts[2], root.systemShortcuts[6]];
            for (let i = 0; i < topShortcuts.length; i++) {
                if (topShortcuts[i]) out.push(topShortcuts[i]);
            }

            // Suggested Top Commands
            const topCmds = [root.suggestedCommands[0], root.suggestedCommands[1], root.suggestedCommands[4]];
            for (let i = 0; i < topCmds.length; i++) {
                if (topCmds[i]) out.push(topCmds[i]);
            }

            root.results = out;
            root.selectedIndex = 0;
            return;
        }

        // ── QUERY STATE: Filter & Score Results ──────────
        let matchedCalc = calcItem;
        let matchedShortcuts = [];
        let matchedCommands = [];
        let matchedApps = [];

        // Check explicit terminal command prefix: e.g. "> ls -la" or "> htop"
        if (rawQ.startsWith(">")) {
            const cmdStr = rawQ.substring(1).trim();
            if (cmdStr) {
                out.push({
                    id: "custom_cmd_" + cmdStr,
                    type: "cmd",
                    title: "Run: " + cmdStr,
                    subtitle: "Execute in Kitty terminal",
                    category: "TOP HIT",
                    kindTag: "Terminal Command",
                    icon: "󰞷",
                    glyph: "󰞷",
                    accentColor: root.theme.accent,
                    cmd: cmdStr,
                    desc: "Runs '" + cmdStr + "' directly in Kitty terminal.",
                    actionLabel: "Run in Kitty",
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

        // A. Match System Shortcuts
        for (let i = 0; i < root.systemShortcuts.length; i++) {
            const sc = root.systemShortcuts[i];
            const titleMatch = sc.title.toLowerCase().includes(q);
            const subMatch = sc.subtitle.toLowerCase().includes(q);
            const kwMatch = sc.keywords.some(k => k.includes(q));
            if (titleMatch || subMatch || kwMatch) {
                matchedShortcuts.push(sc);
            }
        }

        // B. Match Suggested Commands
        for (let i = 0; i < root.suggestedCommands.length; i++) {
            const cmd = root.suggestedCommands[i];
            const titleMatch = cmd.title.toLowerCase().includes(q);
            const cmdMatch = cmd.cmd.toLowerCase().includes(q);
            const kwMatch = cmd.keywords.some(k => k.includes(q));
            if (titleMatch || cmdMatch || kwMatch) {
                matchedCommands.push(cmd);
            }
        }

        // C. Match Desktop Applications
        const allApps = [...(DesktopEntries.applications.values || [])];
        const filtered = allApps.filter(app => {
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

        for (let i = 0; i < Math.min(8, filtered.length); i++) {
            const app = filtered[i];
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

        // D. Top Hit Selection (macOS 1:1 Behavior)
        let topHit = null;

        // If math expression is explicit:
        if (matchedCalc && (rawQ.startsWith("=") || /^[0-9+\-*/().%^ eE]+$/.test(rawQ))) {
            topHit = matchedCalc;
            matchedCalc = null;
        } else if (matchedApps.length > 0 && matchedApps[0].title.toLowerCase().startsWith(q)) {
            // Exact prefix app match is prime top hit candidate
            topHit = matchedApps.shift();
        } else if (matchedShortcuts.length > 0 && matchedShortcuts[0].title.toLowerCase().startsWith(q)) {
            topHit = matchedShortcuts.shift();
        } else if (matchedCommands.length > 0 && matchedCommands[0].cmd.toLowerCase().startsWith(q)) {
            topHit = matchedCommands.shift();
        } else if (matchedApps.length > 0) {
            topHit = matchedApps.shift();
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

        // Add remaining applications
        for (let i = 0; i < matchedApps.length; i++) {
            matchedApps[i].category = "APPLICATIONS";
            out.push(matchedApps[i]);
        }

        // Add remaining shortcuts
        for (let i = 0; i < matchedShortcuts.length; i++) {
            matchedShortcuts[i].category = "SHORTCUTS";
            out.push(matchedShortcuts[i]);
        }

        // Add remaining commands
        for (let i = 0; i < matchedCommands.length; i++) {
            matchedCommands[i].category = "COMMANDS";
            out.push(matchedCommands[i]);
        }

        // If arbitrary command typed, offer terminal execution
        if (rawQ.length > 1 && !topHit && matchedApps.length === 0) {
            out.push({
                id: "typed_cmd_" + rawQ,
                type: "cmd",
                title: "Run: " + rawQ,
                subtitle: "Execute terminal command in Kitty",
                category: "COMMANDS",
                kindTag: "Terminal Command",
                icon: "󰞷",
                glyph: "󰞷",
                accentColor: root.theme.accent,
                cmd: rawQ,
                desc: "Runs '" + rawQ + "' directly in Kitty terminal.",
                actionLabel: "Run in Kitty",
                action: () => root.runTerminalCmd(rawQ, false)
            });
        }

        // E. Web Search Fallback
        out.push({
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
        });

        root.results = out;
        root.selectedIndex = 0;
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

        BackgroundEffect.blurRegion: Region { item: spotlightBox }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Dark Blurred Backdrop (click to dismiss)
        Rectangle {
            anchors.fill: parent
            color: Services.Aesthetic.backdropColor

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeLauncher()
            }
        }

        // ── Spotlight Floating Card (macOS 1:1) ──────
        Rectangle {
            id: spotlightBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.16

            width: 720
            height: 480
            radius: 16
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
                    height: 58
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
                            font.pixelSize: 18
                            font.family: root.font
                            font.weight: Font.Normal
                            clip: true
                            focus: true

                            Text {
                                anchors.fill: parent
                                text: "Spotlight Search"
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
                                if (event.key === Qt.Key_Down) {
                                    event.accepted = true;
                                    if (root.results.length > 0) {
                                        root.selectedIndex = (root.selectedIndex + 1) % root.results.length;
                                        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    }
                                } else if (event.key === Qt.Key_Up) {
                                    event.accepted = true;
                                    if (root.results.length > 0) {
                                        root.selectedIndex = (root.selectedIndex - 1 + root.results.length) % root.results.length;
                                        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    }
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;
                                    root.executeSelectedItem();
                                } else if (event.key === Qt.Key_Tab) {
                                    event.accepted = true;
                                    if (root.results.length > 0) {
                                        root.selectedIndex = (root.selectedIndex + 1) % root.results.length;
                                        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
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

                // ── 2. HORIZONTAL DIVIDER ────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── 3. DUAL-PANE SPOTLIGHT CONTENT ───
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // ── LEFT PANE: RESULTS LIST (width: 420px) ──
                    Rectangle {
                        Layout.preferredWidth: 420
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
                                                visible: modelData.type === "app" && (modelData.icon ?? "") !== ""
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.glyph ?? (modelData.icon ?? "󰣆")
                                                color: root.selectedIndex === index ? "#ffffff" : (modelData.accentColor ?? root.theme.accent)
                                                font.pixelSize: 14
                                                font.family: root.font
                                                visible: modelData.type !== "app" || (modelData.icon ?? "") === ""
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
                        color: Qt.rgba(0, 0, 0, 0.12)
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12

                            // ── TOP: Icon + Large Title + Kind ──
                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                spacing: 8

                                // Large 64x64 Squircle Icon
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 64
                                    height: 64
                                    radius: 14
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 48
                                        height: 48
                                        source: Quickshell.iconPath(root.selectedItem?.icon ?? "", true)
                                        visible: root.selectedItem?.type === "app" && (root.selectedItem?.icon ?? "") !== ""
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.selectedItem?.glyph ?? (root.selectedItem?.icon ?? "󰣆")
                                        color: root.selectedItem?.accentColor ?? root.theme.accent
                                        font.pixelSize: 32
                                        font.family: root.font
                                        visible: root.selectedItem?.type !== "app" || (root.selectedItem?.icon ?? "") === ""
                                    }
                                }

                                // Large Title
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 240
                                    text: root.selectedItem?.title ?? "Spotlight Search"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 15
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
                                    font.pixelSize: 26
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

                            // 2. Standard Metadata Rows (Apps, Shortcuts, Commands)
                            ColumnLayout {
                                visible: root.selectedItem?.type !== "calc"
                                Layout.fillWidth: true
                                spacing: 8

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

                            // ── BOTTOM: Primary Action Button (macOS 1:1) ──
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

                // ── 4. HORIZONTAL DIVIDER ────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── 5. SPOTLIGHT FOOTER BAR ──────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    color: Qt.rgba(0, 0, 0, 0.2)

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
                                Text { text: "Execute"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }

                            Row {
                                spacing: 4
                                Text { text: "esc"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                Text { text: "Close"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
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
