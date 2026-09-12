import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../services" as Services

Scope {
    id: root

    property Theme theme: Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    property bool appleMenuOpen: false

    // Active MPRIS player helper (prioritizes playing, then paused with metadata)
    property var activePlayer: {
        const players = Mpris.players.values;
        if (!players || players.length === 0) return null;
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i];
        }
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Paused && (players[i].trackTitle || players[i].trackArtist)) {
                return players[i];
            }
        }
        for (let i = 0; i < players.length; i++) {
            if (players[i].trackTitle) return players[i];
        }
        return null;
    }

    readonly property bool isMediaPlaying: root.activePlayer?.playbackState === MprisPlaybackState.Playing

    readonly property string mediaTrackString: {
        if (!root.activePlayer) return "";
        const a = root.activePlayer.trackArtist ?? "";
        const t = root.activePlayer.trackTitle ?? "";
        if (a && t) return a + " — " + t;
        return t || a || "";
    }

    // Current Workspace & Active Window Helpers
    readonly property int currentWorkspaceId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property string currentWorkspaceName: Hyprland.focusedWorkspace?.name ?? ("" + currentWorkspaceId)

    // ── Apple-Style Window-Contact & Adaptive Contrast Tokens ──
    property bool hasTopWindow: false

    // When window touches top: solid frosted glass, so foreground is light.
    // When transparent floating on desktop: invert text to dark charcoal if wallpaper top is light!
    readonly property bool barContentLightMode: !root.hasTopWindow && root.theme.barIsLight

    property color barFgPrimary: barContentLightMode ? "#1a1b20" : "#ffffff"
    Behavior on barFgPrimary { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    property color barFgSecondary: barContentLightMode ? Qt.rgba(0.1, 0.1, 0.12, 0.72) : Qt.rgba(1, 1, 1, 0.72)
    Behavior on barFgSecondary { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    property color barFgMuted: barContentLightMode ? Qt.rgba(0.1, 0.1, 0.12, 0.45) : Qt.rgba(1, 1, 1, 0.45)
    Behavior on barFgMuted { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    property color barPillHover: barContentLightMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.14)
    Behavior on barPillHover { ColorAnimation { duration: 150 } }

    property color barDividerColor: barContentLightMode ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(1, 1, 1, 0.18)
    Behavior on barDividerColor { ColorAnimation { duration: 250 } }

    // ── Live Client Tracker (Ground Truth directly from Hyprland IPC) ──
    property var clientCounts: ({})
    property int wsTick: 0

    Process {
        id: clientsProc
        command: ["hyprctl", "-i", "0", "-j", "clients"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text.trim() || "[]");
                    const counts = {};
                    const focused = Hyprland.focusedWorkspace?.id ?? 1;
                    let touchingTop = false;

                    for (let i = 0; i < list.length; i++) {
                        const w = list[i];
                        const ws = w.workspace?.id;
                        if (ws !== undefined && ws !== null) counts[ws] = (counts[ws] || 0) + 1;
                        if (ws === focused && !w.hidden && w.mapped) {
                            if ((w.fullscreen && w.fullscreen > 0) || (w.at && w.at[1] <= 45)) {
                                touchingTop = true;
                            }
                        }
                    }
                    root.clientCounts = counts;
                    root.hasTopWindow = touchingTop;
                    root.wsTick++;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (!clientsProc.running) clientsProc.running = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!clientsProc.running) clientsProc.running = true;
            root.wsTick++;
        }
        function onFocusedWorkspaceChanged() {
            if (!clientsProc.running) clientsProc.running = true;
            root.wsTick++;
        }
        function onActiveToplevelChanged() {
            if (!clientsProc.running) clientsProc.running = true;
            root.wsTick++;
        }
    }

    // Dynamic workspace list: includes persistent 1..5, focused workspace, and any occupied workspace
    readonly property var workspaceList: {
        root.wsTick;
        const set = new Set([1, 2, 3, 4, 5]);
        const focused = Hyprland.focusedWorkspace?.id ?? 1;
        set.add(focused);
        if (root.clientCounts) {
            for (const wsId in root.clientCounts) {
                const id = parseInt(wsId, 10);
                if (!isNaN(id) && root.clientCounts[wsId] > 0) {
                    set.add(id);
                }
            }
        }
        return Array.from(set).sort((a, b) => a - b);
    }

    readonly property int activeWsIndex: {
        const focused = Hyprland.focusedWorkspace?.id ?? 1;
        const list = root.workspaceList;
        return list.indexOf(focused);
    }

    readonly property bool currentWorkspaceEmpty: {
        root.wsTick;
        return (root.clientCounts[currentWorkspaceId] ?? 0) === 0;
    }

    readonly property bool isWorkspaceEmpty: {
        if (currentWorkspaceEmpty) return true;
        if (!Hyprland.activeToplevel) return true;
        if (Hyprland.activeToplevel.workspace) {
            return Hyprland.activeToplevel.workspace.id !== currentWorkspaceId;
        }
        return false;
    }

    readonly property string activeAppClass: {
        if (isWorkspaceEmpty) return "";
        const waylandApp = ToplevelManager?.activeToplevel?.appId ?? "";
        if (waylandApp.length > 0) return waylandApp;
        const top = Hyprland.activeToplevel;
        if (!top) return "";
        return top.lastIpcObject?.["class"] ?? top.waylandHandle?.appId ?? top.lastIpcObject?.["initialClass"] ?? "";
    }
    readonly property string activeAppTitle: {
        if (isWorkspaceEmpty) return "";
        const waylandTitle = ToplevelManager?.activeToplevel?.title ?? "";
        if (waylandTitle.length > 0) return waylandTitle;
        return Hyprland.activeToplevel?.title ?? "";
    }
    readonly property string activeAppName: isWorkspaceEmpty ? "Hyprland" : formatAppName(activeAppClass)

    function formatAppName(cls) {
        if (!cls || cls.length === 0) return "";
        const c = cls.toLowerCase();
        if (c.includes("kitty")) return "Kitty";
        if (c.includes("alacritty")) return "Alacritty";
        if (c.includes("terminal") || c.includes("konsole")) return "Terminal";
        if (c.includes("foot")) return "Foot";
        if (c.includes("wezterm")) return "WezTerm";
        if (c.includes("brave")) return "Brave";
        if (c.includes("firefox")) return "Firefox";
        if (c.includes("chrome") || c.includes("chromium")) return "Chrome";
        if (c.includes("code") || c.includes("codium")) return "VS Code";
        if (c.includes("dolphin")) return "Dolphin";
        if (c.includes("nautilus") || c.includes("thunar") || c.includes("pcmanfm")) return "Files";
        if (c.includes("elisa")) return "Elisa";
        if (c.includes("spotify")) return "Spotify";
        if (c.includes("discord") || c.includes("vesktop") || c.includes("webcord")) return "Discord";
        if (c.includes("steam")) return "Steam";
        if (c.includes("slack")) return "Slack";
        if (c.includes("telegram")) return "Telegram";
        if (c.includes("obs")) return "OBS Studio";
        if (c.includes("gimp")) return "GIMP";
        if (c.includes("inkscape")) return "Inkscape";
        if (c.includes("blender")) return "Blender";
        if (c.includes("mpv")) return "mpv";
        if (c.includes("vlc")) return "VLC";
        return cls.charAt(0).toUpperCase() + cls.slice(1);
    }

    // ═══════════════════════════════════════════
    // TOP MENU BAR (1:1 macOS STYLE - COMFORTABLE PADDING)
    // ═══════════════════════════════════════════
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: 34
            color: "transparent"

            BackgroundEffect.blurRegion: Region { item: barGlassBg }

            // ── Apple-Style Dynamic Glass Background & Micro Scrim ──
            Rectangle {
                id: barGlassBg
                anchors.fill: parent
                color: root.hasTopWindow
                    ? Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.82)
                    : (root.barContentLightMode ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0.04, 0.04, 0.07, 0.40))
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                // Top subtle micro-scrim (improves text contrast over busy wallpapers in transparent mode)
                Rectangle {
                    anchors.fill: parent
                    visible: !root.hasTopWindow
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.theme.barIsLight ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.22) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // Bottom hairline separator when window touches top
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: root.hasTopWindow ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }

            // ── Bar Content ───
            Item {
                anchors.fill: parent

                // ═══════════════════════════════════════
                // LEFT SECTION: Apple  | Workspaces | Active Window
                // ═══════════════════════════════════════
                RowLayout {
                    id: leftSection
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // ── Unified OS System Menu Button (Dynamic Distro Nerd Font) ──
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 26
                        radius: 13
                        color: root.appleMenuOpen || appleMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.SystemService.distroGlyph
                            color: root.appleMenuOpen || appleMouse.containsMouse ? root.theme.accent : root.barFgPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: appleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.appleMenuOpen = !root.appleMenuOpen
                        }
                    }

                    // Subtle Divider
                    Rectangle {
                        width: 1
                        height: 14
                        color: root.barDividerColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // ── Modern Morphing Capsule Workspaces ────────
                    Rectangle {
                        id: wsTrack
                        implicitWidth: wsRow.implicitWidth + 12
                        implicitHeight: 26
                        radius: 13
                        color: root.barContentLightMode ? Qt.rgba(0, 0, 0, 0.07) : Qt.rgba(0, 0, 0, 0.28)
                        border.color: root.barContentLightMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        Layout.alignment: Qt.AlignVCenter

                        // Smooth Gliding Active Capsule (underneath items)
                        Rectangle {
                            id: activeCapsule
                            visible: root.activeWsIndex >= 0 && wsRepeater.count > 0
                            y: (parent.height - height) / 2
                            height: 20
                            radius: 10
                            color: theme.wsActive

                            // Target coordinates based on active workspace item
                            x: {
                                const idx = root.activeWsIndex;
                                if (idx < 0 || idx >= wsRepeater.count) return 4;
                                const it = wsRepeater.itemAt(idx);
                                if (!it) return 4;
                                return wsRow.x + it.x;
                            }
                            width: {
                                const idx = root.activeWsIndex;
                                if (idx < 0 || idx >= wsRepeater.count) return 28;
                                const it = wsRepeater.itemAt(idx);
                                if (!it) return 28;
                                return it.width;
                            }

                            Behavior on x {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            Behavior on width {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }

                        Row {
                            id: wsRow
                            spacing: 4
                            anchors.centerIn: parent

                            Repeater {
                                id: wsRepeater
                                model: root.workspaceList

                                Item {
                                    id: spacePill
                                    required property int index
                                    required property int modelData
                                    readonly property int wsId: modelData
                                    readonly property bool isActive: Hyprland.focusedWorkspace?.id === wsId
                                    readonly property int winCount: {
                                        root.wsTick;
                                        return root.clientCounts ? (root.clientCounts[wsId] ?? 0) : 0;
                                    }
                                    readonly property bool isOccupied: winCount > 0
                                    readonly property bool hasUrgent: {
                                        const vals = Hyprland.workspaces.values;
                                        if (!vals) return false;
                                        for (let i = 0; i < vals.length; i++) {
                                            if (vals[i].id === wsId) return Boolean(vals[i].lastIpcObject?.hasurgent);
                                        }
                                        return false;
                                    }

                                    // Dynamic width: active is 28px, occupied is 24px, empty is 20px (hover adds +2)
                                    width: (isActive ? 28 : (isOccupied ? 24 : 20)) + (spaceMouse.containsMouse && !isActive ? 2 : 0)
                                    height: 20

                                    Behavior on width {
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    // Hover pill for inactive items
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: spaceMouse.containsMouse && !spacePill.isActive ? root.barPillHover : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    // Item Content: Workspace Number & Occupied Indicator Dot
                                    Item {
                                        anchors.centerIn: parent
                                        width: parent.width
                                        height: parent.height

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: spacePill.isOccupied && !spacePill.isActive ? -1 : 0
                                            text: spacePill.wsId
                                            color: spacePill.isActive ? "#ffffff"
                                                 : spacePill.hasUrgent ? "#ff3b30"
                                                 : (spacePill.isOccupied ? root.barFgPrimary : root.barFgMuted)
                                            font.pixelSize: spacePill.isActive ? 12 : 11
                                            font.family: root.font
                                            font.weight: spacePill.isActive ? Font.Bold : (spacePill.isOccupied ? Font.Bold : Font.DemiBold)
                                        }

                                        // Subtle Occupied Dot for background workspaces with active windows
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 2
                                            width: 3
                                            height: 3
                                            radius: 1.5
                                            color: spacePill.hasUrgent ? "#ff3b30" : root.barFgPrimary
                                            visible: spacePill.isOccupied && !spacePill.isActive
                                        }
                                    }

                                    MouseArea {
                                        id: spaceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + spacePill.wsId + " })")
                                    }
                                }
                            }
                        }

                        // Wheel to switch spaces
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) Hyprland.dispatch("hl.dsp.focus({ workspace = 'e-1' })");
                                else Hyprland.dispatch("hl.dsp.focus({ workspace = 'e+1' })");
                            }
                        }
                    }

                    // ── Active Window / Workspace Indicator ─────────
                    Rectangle {
                        id: activeWinPill
                        implicitHeight: 26
                        implicitWidth: activeWinRow.implicitWidth + 14
                        radius: 13
                        color: activeWinMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Layout.alignment: Qt.AlignVCenter

                        RowLayout {
                            id: activeWinRow
                            anchors.centerIn: parent
                            spacing: 6

                            // Icon (App Icon or Hyprland glyph)
                            Item {
                                width: 18
                                height: 18
                                Layout.alignment: Qt.AlignVCenter

                                IconImage {
                                    id: activeAppIconImg
                                    anchors.fill: parent
                                    source: Quickshell.iconPath(root.activeAppClass, true)
                                    visible: !root.isWorkspaceEmpty && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.isWorkspaceEmpty ? "" : "󱂬"
                                    color: root.barFgPrimary
                                    font.pixelSize: 15
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    visible: !activeAppIconImg.visible
                                }
                            }

                            // App Name or "Hyprland" (Bold)
                            Text {
                                text: {
                                    if (root.isWorkspaceEmpty) return "Hyprland";
                                    return root.activeAppName.length > 0 ? root.activeAppName : root.activeAppTitle;
                                }
                                color: root.barFgPrimary
                                font.pixelSize: 13
                                font.family: root.font
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter
                                visible: text.length > 0
                            }

                            // Window Title Snippet or Workspace Name (Subtle, elided)
                            Text {
                                text: {
                                    if (root.isWorkspaceEmpty) {
                                        return "Workspace " + root.currentWorkspaceName;
                                    }
                                    if (root.activeAppName.length === 0) return "";
                                    const t = root.activeAppTitle;
                                    if (!t || t.length === 0) return "";
                                    if (t.toLowerCase() === root.activeAppName.toLowerCase()) return "";
                                    return t;
                                }
                                color: root.barFgSecondary
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.maximumWidth: 240
                                Layout.alignment: Qt.AlignVCenter
                                visible: text.length > 0
                            }
                        }

                        MouseArea {
                            id: activeWinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }

                // ═══════════════════════════════════════
                // CENTER: Dynamic Island sits here via dedicated overlay
                // ═══════════════════════════════════════
                // ═══════════════════════════════════════
                // RIGHT SECTION: Minimal Bold macOS Menu Extras
                // ═══════════════════════════════════════
                RowLayout {
                    id: rightSection
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    // ── 1. System Tray Icons ────────────
                    RowLayout {
                        spacing: 3
                        visible: SystemTray.items.values.length > 0

                        Repeater {
                            model: SystemTray.items

                            MouseArea {
                                id: trayDelegate
                                required property SystemTrayItem modelData

                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton) modelData.activate();
                                    else if (mouse.button === Qt.RightButton && modelData.hasMenu) trayMenuAnchor.open();
                                }

                                IconImage {
                                    anchors.centerIn: parent
                                    source: trayDelegate.modelData.icon
                                    implicitSize: 16
                                }

                                QsMenuAnchor {
                                    id: trayMenuAnchor
                                    menu: trayDelegate.modelData.menu
                                    anchor.window: trayDelegate.QsWindow.window
                                    anchor.adjustment: PopupAdjustment.Flip
                                    anchor.onAnchoring: {
                                        const window = trayDelegate.QsWindow.window;
                                        const rect = window.contentItem.mapFromItem(
                                            trayDelegate, 0, trayDelegate.height,
                                            trayDelegate.width, trayDelegate.height);
                                        trayMenuAnchor.anchor.rect = rect;
                                    }
                                }
                            }
                        }
                    }

                    // ── 2. Volume Icon (macOS-style icon-only) ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: volMacMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.SystemService.volumeMuted ? "󰖁"
                                : Services.SystemService.volume > 50 ? "󰕾" : "󰖀"
                            color: Services.SystemService.volumeMuted ? "#ff453a" : root.barFgPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: volMacMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    Services.SystemService.rescanAudioSinks();
                                    Services.SystemService.rescanAudioSources();
                                    Services.SystemService.openControlCenter("controls", "audio");
                                } else {
                                    Services.SystemService.toggleMute();
                                }
                            }
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) Services.SystemService.adjustVolume(5);
                                else Services.SystemService.adjustVolume(-5);
                            }
                        }
                    }

                    // ── 2b. Global Microphone Status / Privacy Indicator ──
                    Rectangle {
                        visible: Services.SystemService.micMuted || Services.SystemService.micInUse
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: Services.SystemService.micMuted
                            ? (micBarMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.28) : Qt.rgba(1, 0.27, 0.23, 0.16))
                            : (micBarMouse.containsMouse ? Qt.rgba(1, 0.58, 0.0, 0.28) : Qt.rgba(1, 0.58, 0.0, 0.16))
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                            color: Services.SystemService.micMuted ? "#ff453a" : "#ff9f0a"
                            font.pixelSize: 15
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: micBarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    Services.SystemService.rescanAudioSources();
                                    Services.SystemService.openControlCenter("controls", "audio");
                                } else {
                                    Services.SystemService.toggleMicMute();
                                }
                            }
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) Services.SystemService.adjustMicVolume(5);
                                else Services.SystemService.adjustMicVolume(-5);
                            }
                        }
                    }


                    // ── 3. Night Shift Indicator ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        visible: Services.NightLightService.active
                        color: nsBarMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰔎"
                            color: "#ff9f0a"
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: nsBarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.NightLightService.toggle()
                        }
                    }

                    // ── 3b. Caffeine Indicator ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        visible: Services.SystemService.caffeineActive
                        color: caffBarMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅶"
                            color: "#ff9f0a"
                            font.pixelSize: 15
                            font.family: root.font
                        }

                        MouseArea {
                            id: caffBarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemService.toggleCaffeine()
                        }
                    }

                    // ── 4. Battery Widget (horizontal capsule, % on hover) ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: battMacRow.implicitWidth + 10
                        radius: 13
                        color: battMacMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: battMacRow
                            anchors.centerIn: parent
                            spacing: 5

                            Item {
                                id: battIconItem
                                width: 25
                                implicitWidth: 25
                                height: 12
                                implicitHeight: 12
                                anchors.verticalCenter: parent.verticalCenter

                                readonly property color battColor: {
                                    if (Services.SystemService.batteryLevel <= 20 && !Services.SystemService.batteryCharging) return "#ff453a";
                                    if (Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged) return "#30d158";
                                    return root.barFgPrimary;
                                }

                                // Outer capsule
                                Rectangle {
                                    id: battBody
                                    width: 22
                                    height: 11
                                    radius: 3
                                    color: root.barContentLightMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: Qt.rgba(battIconItem.battColor.r, battIconItem.battColor.g, battIconItem.battColor.b, 0.8)
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter

                                    // Dynamic level fill
                                    Rectangle {
                                        id: battFill
                                        anchors.left: parent.left
                                        anchors.leftMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height - 4
                                        radius: 1.5
                                        color: battIconItem.battColor
                                        width: Math.max(Services.SystemService.batteryLevel > 0 ? 2 : 0,
                                                        Math.min(parent.width - 4, (parent.width - 4) * (Services.SystemService.batteryLevel / 100)))

                                        Behavior on width {
                                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                        }
                                    }

                                    // Charging lightning bolt
                                    Text {
                                        anchors.centerIn: parent
                                        visible: Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged
                                        text: "󱐋"
                                        font.family: root.font
                                        font.pixelSize: 9
                                        font.weight: Font.Black
                                        color: Services.SystemService.batteryLevel > 45 ? "#000000" : battIconItem.battColor
                                    }
                                }

                                // Positive terminal nub
                                Rectangle {
                                    id: battNub
                                    width: 1.5
                                    height: 4
                                    radius: 0.75
                                    color: Qt.rgba(battIconItem.battColor.r, battIconItem.battColor.g, battIconItem.battColor.b, 0.8)
                                    anchors.left: battBody.right
                                    anchors.leftMargin: 1
                                    anchors.verticalCenter: battBody.verticalCenter
                                }
                            }

                            Text {
                                text: Services.SystemService.batteryLevel + "%"
                                color: root.barFgPrimary
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                                visible: battMacMouse.containsMouse
                                width: visible ? implicitWidth : 0
                                clip: true
                                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: battMacMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemService.toggleControlCenter()
                        }
                    }

                    // ── 5. Wi-Fi Icon ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: wifiIconMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.SystemService.networkType === "ethernet" ? "󰈀"
                                : Services.SystemService.networkType === "wifi" ? "󰖩" : "󰖪"
                            color: Services.SystemService.networkType === "disconnected" ? root.barFgMuted : root.barFgPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: wifiIconMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.SystemService.rescanWifi();
                                Services.SystemService.openControlCenter("controls", "wifi");
                            }
                        }
                    }

                    // ── 6. Bluetooth Icon ──
                    Rectangle {
                        visible: Services.SystemService.bluetoothEnabled
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: (Services.SystemService.controlCenterOpen && Services.SystemService.controlCenterSubView === "bluetooth") || btIconMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰂯"
                            color: Services.SystemService.bluetoothDevices.some(d => d.connected) ? theme.accent : root.barFgPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: btIconMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.SystemService.rescanBluetooth();
                                Services.SystemService.openControlCenter("controls", "bluetooth");
                            }
                        }
                    }

                    // ── 7. Spotlight Search Icon ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: spotIconMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰍉"
                            color: root.barFgPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: spotIconMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemService.runCmd("quickshell ipc call launcher toggle")
                        }
                    }

                    // ── 8. Control Center Icon (macOS switch.2) ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: (Services.SystemService.controlCenterOpen && Services.SystemService.controlCenterTab === "controls") || ccIconMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Item {
                            anchors.centerIn: parent
                            width: 16
                            height: 12

                            property color iconColor: (Services.SystemService.controlCenterOpen && Services.SystemService.controlCenterTab === "controls") ? theme.accent : root.barFgPrimary
                            Behavior on iconColor { ColorAnimation { duration: 120 } }

                            // Top Toggle Switch (knob on right)
                            Rectangle {
                                y: 0
                                width: 16
                                height: 5
                                radius: 2.5
                                color: "transparent"
                                border.color: parent.iconColor
                                border.width: 1.2

                                Rectangle {
                                    x: parent.width - width - 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: parent.border.color
                                }
                            }

                            // Bottom Toggle Switch (knob on left)
                            Rectangle {
                                y: 7
                                width: 16
                                height: 5
                                radius: 2.5
                                color: "transparent"
                                border.color: parent.iconColor
                                border.width: 1.2

                                Rectangle {
                                    x: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: parent.border.color
                                }
                            }
                        }

                        MouseArea {
                            id: ccIconMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.ClockService.calendarOpen = false;
                                Services.SystemService.openControlCenter("controls", "main");
                            }
                        }
                    }

                    // ── 9. Notification Bell ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: 26
                        radius: 13
                        color: (Services.SystemService.controlCenterOpen && Services.SystemService.controlCenterTab === "notifications") || notifBellMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.NotificationService.dnd ? "󰂛" : "󰂚"
                            color: Services.NotificationService.dnd ? theme.accentMauve : ((Services.SystemService.controlCenterOpen && Services.SystemService.controlCenterTab === "notifications") ? theme.accent : root.barFgPrimary)
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        // Unread Dot
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: theme.accentRed
                            anchors.top: parent.top
                            anchors.topMargin: 3
                            anchors.right: parent.right
                            anchors.rightMargin: 3
                            visible: Services.NotificationService.unreadCount > 0 && !Services.NotificationService.dnd
                        }

                        MouseArea {
                            id: notifBellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.ClockService.calendarOpen = false;
                                Services.SystemService.openControlCenter("notifications", "main");
                            }
                        }
                    }

                    // Subtle Divider before Clock
                    Rectangle {
                        width: 1
                        height: 14
                        color: root.barDividerColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // ── 10. Clock (Opens Calendar) ──
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: clockMacText.implicitWidth + 14
                        radius: 13
                        color: Services.ClockService.calendarOpen || clockMacMouse.containsMouse ? root.barPillHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: clockMacText
                            anchors.centerIn: parent
                            text: Services.ClockService.macClock
                            color: root.barFgPrimary
                            font.pixelSize: 13
                            font.family: root.font
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: clockMacMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.SystemService.controlCenterOpen = false;
                                Services.ClockService.toggleCalendar();
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // APPLE MENU DROPDOWN ()
    // ═══════════════════════════════════════════
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: appleMenuWindow
            required property var modelData
            screen: modelData

            visible: root.appleMenuOpen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-apple-menu"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: appleMenuCard }

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // Click backdrop to dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: root.appleMenuOpen = false
            }

            // Dropdown Menu Card (macOS Tahoe Glass)
            Rectangle {
                id: appleMenuCard
                anchors.top: parent.top
                anchors.topMargin: 38
                anchors.left: parent.left
                anchors.leftMargin: 8

                width: 232
                height: menuCol.implicitHeight + 14
                radius: 14
                color: Qt.rgba(0.11, 0.12, 0.16, 0.78)
                border.color: Qt.rgba(1, 1, 1, 0.16)
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                Column {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    // 1. About This Machine
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm1.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰌢"; color: itm1.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "About This Machine"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font; font.weight: Font.Medium }
                        }
                        MouseArea {
                            id: itm1
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.aboutDialogOpen = true;
                            }
                        }
                    }

                    // 2. System Settings
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm2.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰒓"; color: itm2.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "System Settings..."; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("systemsettings || kitty");
                            }
                        }
                    }

                    // 3. Spotlight
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm3.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰍉"; color: itm3.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Spotlight Search"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                            Item { Layout.fillWidth: true }
                            Text { text: "⌥ Space"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                        }
                        MouseArea {
                            id: itm3
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("quickshell ipc call launcher toggle");
                            }
                        }
                    }

                    // Divider
                    Rectangle { width: parent.width - 12; height: 1; color: Qt.rgba(1, 1, 1, 0.07); anchors.horizontalCenter: parent.horizontalCenter }

                    // 4. Terminal
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm4.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰞷"; color: itm4.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Terminal"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm4
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.openTerminal();
                            }
                        }
                    }

                    // 5. Files
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm5.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰉋"; color: itm5.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Finder / Files"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm5
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.openFileManager();
                            }
                        }
                    }

                    // Divider
                    Rectangle { width: parent.width - 12; height: 1; color: Qt.rgba(1, 1, 1, 0.07); anchors.horizontalCenter: parent.horizontalCenter }

                    // 6. Sleep
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm6.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰤄"; color: itm6.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Sleep"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm6
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("systemctl suspend");
                            }
                        }
                    }

                    // 7. Restart
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm7.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰜉"; color: itm7.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Restart..."; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm7
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("systemctl reboot");
                            }
                        }
                    }

                    // 8. Shut Down
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm8.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.14) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "⏻"; color: itm8.containsMouse ? "#ff453a" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Shut Down..."; color: itm8.containsMouse ? "#ff453a" : root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm8
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("systemctl poweroff");
                            }
                        }
                    }

                    // Divider
                    Rectangle { width: parent.width - 12; height: 1; color: Qt.rgba(1, 1, 1, 0.07); anchors.horizontalCenter: parent.horizontalCenter }

                    // 9. Lock Screen
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm9.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰌾"; color: itm9.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Lock Screen"; color: root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm9
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.lockScreen();
                            }
                        }
                    }

                    // 10. Log Out
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 8
                        color: itm10.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.14) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8
                            Text { text: "󰍃"; color: itm10.containsMouse ? "#ff453a" : root.theme.textSecondary; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Log Out " + Services.SystemService.homeDir.replace('/home/', '') + "..."; color: itm10.containsMouse ? "#ff453a" : root.theme.textPrimary; font.pixelSize: 12; font.family: root.font }
                        }
                        MouseArea {
                            id: itm10
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.appleMenuOpen = false;
                                Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.exit()'");
                            }
                        }
                    }
                }
            }
        }
    }
}
