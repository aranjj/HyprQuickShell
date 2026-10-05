import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    // Sub-view toggle: "main", "wifi", "bluetooth", "audio", "battery", "media"
    readonly property string activeView: Services.SystemService.controlCenterSubView

    IpcHandler {
        target: "controlcenter"

        function toggle() {
            Services.SystemService.toggleControlCenter();
        }

        function open() {
            Services.SystemService.openControlCenter("controls", "main");
        }

        function openNotifications() {
            Services.SystemService.openNotificationCenter();
        }

        function openSub(sub: string) {
            Services.SystemService.openControlCenter("controls", sub || "main");
        }

        function promptWifi(ssid: string) {
            Services.SystemService.controlCenterOpen = true;
            Services.SystemService.controlCenterSubView = "wifi";
            root.wifiJoinOtherMode = false;
            root.wifiPromptSsid = ssid || "";
        }

        function promptJoinOther() {
            Services.SystemService.controlCenterOpen = true;
            Services.SystemService.controlCenterSubView = "wifi";
            root.wifiPromptSsid = "";
            root.wifiJoinOtherMode = true;
            root.wifiOtherSsid = "";
            root.wifiOtherPassword = "";
            root.wifiShowPasswordText = false;
            Services.SystemService.wifiConnectError = "";
        }

        function close() {
            Services.SystemService.controlCenterOpen = false;
        }

        function setProfile(profile: string) {
            Services.SystemService.setPowerProfile(profile);
        }

        function cycleProfile() {
            Services.SystemService.cyclePowerProfile();
        }
    }

    // Quick toggles states
    property bool dndEnabled: false
    property bool nightShiftEnabled: false
    property bool soundOutputsOpen: false
    property bool soundInputsOpen: false

    // Preferred MPRIS player identity
    property string preferredPlayerIdentity: ""

    // Active MPRIS player helper (intelligently scored & prioritized)
    property var activePlayer: {
        const players = Mpris.players.values;
        if (!players || players.length === 0) return null;

        let bestPlayer = null;
        let bestScore = -99999;

        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p) continue;

            let score = 0;

            // Preferred player bonus
            if (preferredPlayerIdentity && p.identity === preferredPlayerIdentity) {
                score += 50000;
            }

            // 1. Playback state
            if (p.playbackState === MprisPlaybackState.Playing) {
                score += 10000;
            } else if (p.playbackState === MprisPlaybackState.Paused) {
                score += 5000;
            } else {
                score += 1000;
            }

            // 2. Track artwork presence (critical for rich media UI)
            const art = p.trackArtUrl ? ("" + p.trackArtUrl).trim() : "";
            if (art.length > 0) {
                score += 3000;
            }

            // 3. Artist presence
            const artist = p.trackArtist ? ("" + p.trackArtist).trim() : "";
            if (artist.length > 0) {
                score += 500;
            }

            // 4. Title presence
            const title = p.trackTitle ? ("" + p.trackTitle).trim() : "";
            if (title.length > 0) {
                score += 300;
            }

            // 5. Prefer rich players / browser integration over bare browser instances
            const id = ((p.identity || "") + " " + (p.busName || "")).toLowerCase();
            if (id.includes("plasma-browser-integration")) {
                score += 1500;
            } else if (id.includes("spotify") || id.includes("cider") || id.includes("rhythmbox") || id.includes("amberol")) {
                score += 1000;
            } else if (id.includes("firefox.instance") || id.includes("chromium.instance")) {
                if (!art) score -= 2000;
            }

            if (score > bestScore) {
                bestScore = score;
                bestPlayer = p;
            }
        }

        return bestPlayer;
    }

    // ── Persistent Album Art Tracking ────────────────────
    property string lastLoadedArtUrl: ""
    property string lastTrackTitle: ""

    readonly property string rawTrackArt: {
        const p = root.activePlayer;
        if (!p) return "";
        let url = p.trackArtUrl ? ("" + p.trackArtUrl).trim() : "";
        if (url.startsWith("/")) url = "file://" + url;
        return url;
    }

    readonly property string currentTrackTitle: root.activePlayer?.trackTitle ? ("" + root.activePlayer.trackTitle).trim() : ""

    onRawTrackArtChanged: {
        if (rawTrackArt !== "") {
            root.lastLoadedArtUrl = rawTrackArt;
            artClearTimer.stop();
        } else if (currentTrackTitle !== root.lastTrackTitle) {
            artClearTimer.restart();
        }
    }

    onCurrentTrackTitleChanged: {
        if (currentTrackTitle !== "" && currentTrackTitle !== root.lastTrackTitle) {
            root.lastTrackTitle = currentTrackTitle;
            if (rawTrackArt !== "") {
                root.lastLoadedArtUrl = rawTrackArt;
                artClearTimer.stop();
            } else {
                artClearTimer.restart();
            }
        } else if (!root.activePlayer || currentTrackTitle === "") {
            root.lastLoadedArtUrl = "";
            root.lastTrackTitle = "";
            artClearTimer.stop();
        }
    }

    Timer {
        id: artClearTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (root.rawTrackArt === "") {
                root.lastLoadedArtUrl = "";
            }
        }
    }

    readonly property string displayTrackArt: {
        if (rawTrackArt !== "") return rawTrackArt;
        if (root.lastLoadedArtUrl !== "") return root.lastLoadedArtUrl;
        return "";
    }

    readonly property bool isMediaPlaying: root.activePlayer?.playbackState === MprisPlaybackState.Playing

    // Player Accent Color
    readonly property color playerAccent: {
        const id = (root.activePlayer?.identity ?? "").toLowerCase();
        if (id.includes("spotify")) return "#1db954";
        return root.theme.accent;
    }

    function formatTime(secs) {
        if (isNaN(secs) || secs < 0) return "0:00";
        const total = Math.floor(secs);
        const m = Math.floor(total / 60);
        const rem = total % 60;
        return m + ":" + (rem < 10 ? "0" : "") + rem;
    }

    function seekTo(targetSecs) {
        if (!root.activePlayer) return;
        const len = root.activePlayer.length ?? 0;
        const maxSec = len > 1 ? len - 1 : (len > 0 ? len : targetSecs);
        const clamped = Math.max(0, Math.min(targetSecs, maxSec));

        try {
            root.activePlayer.position = clamped;
        } catch (e) {}

        Services.SystemService.runCmd("playerctl position " + clamped.toFixed(1));
    }

    function seekRelative(deltaSecs) {
        if (!root.activePlayer) return;
        const cur = root.activePlayer.position ?? 0;
        seekTo(cur + deltaSecs);
    }

    function getBtIcon(iconType) {
        if (!iconType) return "󰂯";
        switch (iconType) {
            case "headphones": return "󰋋";
            case "speaker": return "󰓃";
            case "mouse": return "󰍽";
            case "keyboard": return "󰌌";
            case "controller": return "󰊴";
            case "phone": return "󰏲";
            case "laptop": return "󰌢";
            case "tv": return "󰍹";
            case "watch": return "󰱱";
            default: return "󰂯";
        }
    }

    function getWifiSignalIcon(signal) {
        const s = signal || 0;
        if (s >= 75) return "󰤨";
        if (s >= 50) return "󰤥";
        if (s >= 25) return "󰤢";
        return "󰤟";
    }

    property string wifiPromptSsid: ""
    property string wifiPasswordText: ""
    property bool wifiShowPasswordText: false
    property bool wifiShowActiveDetails: false
    property bool wifiShowOtherNetworkModal: false
    property bool wifiJoinOtherMode: false
    property string wifiOtherSsid: ""
    property string wifiOtherPassword: ""

    readonly property var targetPromptNetwork: {
        if (!root.wifiPromptSsid) return null;
        const others = Services.SystemService.wifiOtherNetworks || [];
        for (let i = 0; i < others.length; i++) {
            if (others[i].ssid === root.wifiPromptSsid) return others[i];
        }
        const known = Services.SystemService.wifiKnownNetworks || [];
        for (let i = 0; i < known.length; i++) {
            if (known[i].ssid === root.wifiPromptSsid) return known[i];
        }
        return { ssid: root.wifiPromptSsid, signal: 70, security: "WPA/WPA2", band: "2.4 GHz", is_locked: true };
    }

    Connections {
        target: Services.SystemService

        function checkAutoDismiss() {
            if (!Services.SystemService.wifiConnected || Services.SystemService.wifiConnecting || Services.SystemService.wifiConnectError) {
                return;
            }
            if (root.wifiPromptSsid !== "" && Services.SystemService.wifiSsid === root.wifiPromptSsid) {
                root.wifiPromptSsid = "";
                root.wifiPasswordText = "";
                root.wifiShowPasswordText = false;
                Services.SystemService.wifiConnectError = "";
            } else if (root.wifiJoinOtherMode && root.wifiOtherSsid.trim() !== "" && Services.SystemService.wifiSsid === root.wifiOtherSsid.trim()) {
                root.wifiJoinOtherMode = false;
                root.wifiOtherSsid = "";
                root.wifiOtherPassword = "";
                root.wifiShowPasswordText = false;
                Services.SystemService.wifiConnectError = "";
            }
        }

        function onWifiConnectedChanged() {
            checkAutoDismiss();
        }

        function onWifiSsidChanged() {
            checkAutoDismiss();
        }

        function onControlCenterSubViewChanged() {
            if (Services.SystemService.controlCenterSubView === "audio") {
                root.soundOutputsOpen = false;
                root.soundInputsOpen = false;
            }
        }

        function onControlCenterOpenChanged() {
            if (!Services.SystemService.controlCenterOpen) {
                root.soundOutputsOpen = false;
                root.soundInputsOpen = false;
            }
        }
    }

    property bool isUserScrubbing: false
    property int clockTick: 0

    Timer {
        id: ccPlaybackClock
        interval: 200
        repeat: true
        running: root.isMediaPlaying && root.activeView === "media"
        onTriggered: root.clockTick++
    }

    // Live Cava Audio Visualizer in Control Center
    property real cavaBar0: 0.0
    property real cavaBar1: 0.0
    property real cavaBar2: 0.0
    property real cavaBar3: 0.0

    Process {
        id: ccCavaProc
        command: ["cava", "-p", "/home/aran/.config/quickshell/cava.conf"]
        running: root.isMediaPlaying && Services.SystemService.controlCenterOpen
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const line = data.trim();
                if (!line) return;
                const parts = line.split(";");
                if (parts.length >= 4) {
                    const b0 = Math.max(0.0, Math.min(1.0, (parseFloat(parts[0]) || 0) / 100.0));
                    const b1 = Math.max(0.0, Math.min(1.0, (parseFloat(parts[1]) || 0) / 100.0));
                    const b2 = Math.max(0.0, Math.min(1.0, (parseFloat(parts[2]) || 0) / 100.0));
                    const b3 = Math.max(0.0, Math.min(1.0, (parseFloat(parts[3]) || 0) / 100.0));
                    root.cavaBar0 = b0;
                    root.cavaBar1 = b1;
                    root.cavaBar2 = b2;
                    root.cavaBar3 = b3;
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: controlCenterWindow
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isOpen: Services.SystemService.controlCenterOpen
            visible: isOpen || closeAnimTimer.running
            color: "transparent"

            Timer {
                id: closeAnimTimer
                interval: 200
                repeat: false
            }

            onIsOpenChanged: {
                if (!isOpen) closeAnimTimer.restart();
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.activeView === "wifi" && (root.wifiPromptSsid !== "" || root.wifiShowOtherNetworkModal || root.wifiJoinOtherMode)) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-control-center"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: card }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // Click outside to dismiss (transparent backdrop)
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Services.SystemService.controlCenterOpen = false;
                    Services.SystemService.controlCenterSubView = "main";
                }
            }

            // ── macOS Style Floating Bezel Card ─────────
            Rectangle {
                id: card
                width: 382
                readonly property bool isControlsMain: root.activeView === "main"
                readonly property bool isCompact: controlCenterWindow.screen.height < 600
                readonly property real maxCardHeight: controlCenterWindow.screen.height - (controlCenterWindow.isOpen ? 44 : 26) - 14
                readonly property real subViewMaxHeight: Math.min(580, maxCardHeight)

                readonly property real activeSubViewHeight: {
                    switch (root.activeView) {
                        case "wifi":
                            if (!Services.SystemService.wifiEnabled) return 240;
                            if (root.wifiPromptSsid !== "") {
                                return Math.min(subViewMaxHeight, Math.max(260, (wifiPasswordView ? wifiPasswordView.implicitHeight : 0) + 76));
                            }
                            if (root.wifiJoinOtherMode) {
                                return Math.min(subViewMaxHeight, Math.max(300, (wifiJoinOtherView ? wifiJoinOtherView.implicitHeight : 0) + 76));
                            }
                            return Math.min(subViewMaxHeight, Math.max(280, (wifiContentCol ? wifiContentCol.implicitHeight : 0) + 88));
                        case "bluetooth":
                            return !Services.SystemService.bluetoothEnabled
                                ? 240
                                : Math.min(subViewMaxHeight, Math.max(280, (btContentCol ? btContentCol.implicitHeight : 0) + 138));
                        case "audio":
                            return Math.min(maxCardHeight, Math.max(280, (audioDetailCol ? audioDetailCol.implicitHeight : 0) + 86));
                        case "battery":
                            return Math.min(subViewMaxHeight, Math.max(280, (battDetailCol ? battDetailCol.implicitHeight : 0) + 86));
                        case "displays":
                            return Math.min(subViewMaxHeight, Math.max(280, (dispCol ? dispCol.implicitHeight : 0) + 86));
                        case "media":
                            return Math.min(subViewMaxHeight, Mpris.players.values.length > 0 ? (384 + Math.min(194, Mpris.players.values.length * 50)) : 358);
                        default:
                            return mainContentCol.implicitHeight + 24;
                    }
                }

                height: Math.min(maxCardHeight, isControlsMain ? (mainContentCol.implicitHeight + 24) : activeSubViewHeight)
                anchors.top: parent.top
                anchors.topMargin: controlCenterWindow.isOpen ? 44 : 26
                anchors.right: parent.right
                anchors.rightMargin: 14
                scale: controlCenterWindow.isOpen ? 1.0 : 0.94
                opacity: controlCenterWindow.isOpen ? 1.0 : 0.0
                transformOrigin: Item.TopRight

                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Prevent click dismissal
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                // ═══════════════════════════════════════════
                // macOS CONTROL CENTER MAIN GRID
                // ═══════════════════════════════════════════
                Flickable {
                    id: mainFlickable
                    visible: root.activeView === "main"
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    contentHeight: mainContentCol.implicitHeight
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: mainContentCol
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 0
                        spacing: card.isCompact ? 6 : 8

                        // ═══════════════════════════════════════════
                        // 1. TOP QUADRANT: Connectivity (Left) & Quick Utility Tiles (Right)
                        // ═══════════════════════════════════════════
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: card.isCompact ? 6 : 8

                            // Left: Connectivity 2x2 Capsule Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 184
                                implicitHeight: card.isCompact ? 128 : 140
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 8 : 10
                                    spacing: card.isCompact ? 2 : 4

                                    // Wi-Fi Row
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: card.isCompact ? 34 : 38
                                        radius: 10
                                        color: wifiRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                             Rectangle {
                                                 width: 30
                                                 height: 30
                                                 radius: 15
                                                 color: Services.SystemService.wifiEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.09)
                                                 Behavior on color { ColorAnimation { duration: 120 } }

                                                 Text {
                                                     anchors.centerIn: parent
                                                     text: ""
                                                     color: Services.SystemService.wifiEnabled ? "#ffffff" : root.theme.textMuted
                                                     font.pixelSize: 14
                                                     font.family: root.font
                                                 }

                                                 MouseArea {
                                                     anchors.fill: parent
                                                     cursorShape: Qt.PointingHandCursor
                                                     onClicked: Services.SystemService.toggleWifi()
                                                 }
                                             }

                                             ColumnLayout {
                                                 Layout.fillWidth: true
                                                 spacing: 1

                                                 Text {
                                                     text: "Wi-Fi"
                                                     color: root.theme.textPrimary
                                                     font.pixelSize: 12
                                                     font.family: root.font
                                                     font.weight: Font.DemiBold
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                                 Text {
                                                     text: Services.SystemService.wifiEnabled ? (Services.SystemService.wifiSsid || "Not Connected") : "Off"
                                                     color: root.theme.textMuted
                                                     font.pixelSize: 11
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
                                                 opacity: wifiRowMouse.containsMouse ? 0.9 : 0.45
                                                 Behavior on opacity { NumberAnimation { duration: 120 } }
                                                 font.pixelSize: 15
                                                 font.family: root.font
                                             }
                                         }

                                        MouseArea {
                                            id: wifiRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.rescanWifi();
                                                Services.SystemService.controlCenterSubView = "wifi";
                                            }
                                        }
                                    }

                                    // Bluetooth Row
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: card.isCompact ? 34 : 38
                                        radius: 10
                                        color: btRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                             Rectangle {
                                                 width: 30
                                                 height: 30
                                                 radius: 15
                                                 color: Services.SystemService.bluetoothEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.09)
                                                 Behavior on color { ColorAnimation { duration: 120 } }

                                                 Text {
                                                     anchors.centerIn: parent
                                                     text: "󰂯"
                                                     color: Services.SystemService.bluetoothEnabled ? "#ffffff" : root.theme.textMuted
                                                     font.pixelSize: 15
                                                     font.family: root.font
                                                 }

                                                 MouseArea {
                                                     anchors.fill: parent
                                                     cursorShape: Qt.PointingHandCursor
                                                     onClicked: Services.SystemService.toggleBluetooth()
                                                 }
                                             }

                                             ColumnLayout {
                                                 Layout.fillWidth: true
                                                 spacing: 1

                                                 Text {
                                                     text: "Bluetooth"
                                                     color: root.theme.textPrimary
                                                     font.pixelSize: 12
                                                     font.family: root.font
                                                     font.weight: Font.DemiBold
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                                 Text {
                                                     text: {
                                                         if (!Services.SystemService.bluetoothEnabled) return "Off";
                                                         const devs = Services.SystemService.bluetoothDevices || [];
                                                         for (let i = 0; i < devs.length; i++) {
                                                             if (devs[i].connected) return devs[i].name || "Connected";
                                                         }
                                                         return "On";
                                                     }
                                                     color: root.theme.textMuted
                                                     font.pixelSize: 11
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
                                                 opacity: btRowMouse.containsMouse ? 0.9 : 0.45
                                                 Behavior on opacity { NumberAnimation { duration: 120 } }
                                                 font.pixelSize: 15
                                                 font.family: root.font
                                             }
                                         }

                                        MouseArea {
                                            id: btRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.startBluetoothScan();
                                                Services.SystemService.controlCenterSubView = "bluetooth";
                                            }
                                        }
                                    }

                                    // AirDrop / LocalSend Row
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: card.isCompact ? 34 : 38
                                        radius: 10
                                        color: shareRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                             Rectangle {
                                                 width: 30
                                                 height: 30
                                                 radius: 15
                                                 color: root.theme.accent
                                                 Behavior on color { ColorAnimation { duration: 120 } }

                                                 Text {
                                                     anchors.centerIn: parent
                                                     text: "󰅠"
                                                     color: "#ffffff"
                                                     font.pixelSize: 14
                                                     font.family: root.font
                                                 }
                                             }

                                             ColumnLayout {
                                                 Layout.fillWidth: true
                                                 spacing: 1

                                                 Text {
                                                     text: "AirDrop"
                                                     color: root.theme.textPrimary
                                                     font.pixelSize: 12
                                                     font.family: root.font
                                                     font.weight: Font.DemiBold
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                                 Text {
                                                     text: "LocalSend"
                                                     color: root.theme.textMuted
                                                     font.pixelSize: 11
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
                                                 opacity: shareRowMouse.containsMouse ? 0.9 : 0.45
                                                 Behavior on opacity { NumberAnimation { duration: 120 } }
                                                 font.pixelSize: 15
                                                 font.family: root.font
                                             }
                                         }

                                        MouseArea {
                                            id: shareRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.runCmd("localsend || kdeconnect-app");
                                                Services.SystemService.controlCenterOpen = false;
                                            }
                                        }
                                    }
                                }
                            }

                            // Right: macOS Tahoe Now Playing Card
                            Rectangle {
                                Layout.preferredWidth: 154
                                Layout.minimumWidth: 154
                                Layout.maximumWidth: 154
                                implicitHeight: card.isCompact ? 128 : 140
                                radius: 16
                                color: mediaCardMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                clip: true
                                Behavior on color { ColorAnimation { duration: 120 } }

                                // Entire card clickable zone (opens Now Playing detail view)
                                MouseArea {
                                    id: mediaCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.controlCenterSubView = "media"
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 8 : 10
                                    spacing: 0

                                    // Top Header: Thumbnail + Track Info + Cava Waveform + Expand Chevron
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Thumbnail / Art (slightly rounded radius 8)
                                        Rectangle {
                                            id: ccIosThumbBox
                                            width: card.isCompact ? 38 : 46
                                            height: card.isCompact ? 38 : 46
                                            radius: 8
                                            color: Services.Aesthetic.innerCardBg
                                            border.color: Services.Aesthetic.innerCardBorder
                                            border.width: 1
                                            Layout.alignment: Qt.AlignVCenter

                                            Image {
                                                id: ccIosThumb
                                                anchors.fill: parent
                                                source: root.displayTrackArt
                                                fillMode: Image.PreserveAspectCrop
                                                visible: false
                                                asynchronous: true
                                                cache: true
                                                sourceSize.width: 100
                                                sourceSize.height: 100
                                            }

                                            Rectangle {
                                                id: ccIosThumbMask
                                                anchors.fill: parent
                                                radius: 8
                                                color: "#ffffff"
                                                antialiasing: true
                                                visible: false
                                                layer.enabled: true
                                            }

                                            MultiEffect {
                                                id: ccIosThumbEffect
                                                anchors.fill: parent
                                                source: ccIosThumb
                                                maskEnabled: true
                                                maskSource: ccIosThumbMask
                                                visible: ccIosThumb.status === Image.Ready && root.displayTrackArt !== ""
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 8
                                                color: "transparent"
                                                border.color: ccIosThumbBox.border.color
                                                border.width: ccIosThumbBox.border.width
                                                antialiasing: true
                                                z: 2
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰝚"
                                                color: "#fa2d48"
                                                opacity: root.activePlayer ? 1.0 : 0.4
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                                font.pixelSize: 22
                                                font.family: root.font
                                                visible: !ccIosThumbEffect.visible
                                            }
                                        }

                                        // Track Info + Live Beat Cava Waveform
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2

                                            Text {
                                                text: {
                                                    if (!root.activePlayer) return "Not Playing";
                                                    return root.activePlayer.trackTitle || "Media Player";
                                                }
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: root.activePlayer?.trackArtist || ""
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                visible: text !== ""
                                            }

                                            // Live Beat Cava Waveform
                                            Row {
                                                visible: !!root.activePlayer
                                                spacing: 2
                                                height: 10
                                                Layout.topMargin: 1

                                                Repeater {
                                                    model: [root.cavaBar0, root.cavaBar1, root.cavaBar2, root.cavaBar3]
                                                    Rectangle {
                                                        required property real modelData
                                                        width: 2
                                                        height: Math.max(2, modelData * 9)
                                                        radius: 1
                                                        color: root.isMediaPlaying ? root.playerAccent : root.theme.textMuted
                                                        anchors.bottom: parent.bottom
                                                        Behavior on height {
                                                            NumberAnimation { duration: 60; easing.type: Easing.Linear }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Expand chevron to full media view
                                        Text {
                                            text: "›"
                                            color: mediaCardMouse.containsMouse ? root.theme.textPrimary : root.theme.textMuted
                                            opacity: mediaCardMouse.containsMouse ? 0.9 : 0.45
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            font.pixelSize: 16
                                            font.family: root.font
                                            Layout.alignment: Qt.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                    }

                                    Item {
                                        Layout.fillHeight: true
                                    }

                                    // Bottom Playback Controls: ⏮  ⏯  ⏭
                                    RowLayout {
                                        id: mediaControlsRow
                                        Layout.fillWidth: true
                                        opacity: root.activePlayer ? 1.0 : 0.4
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 4
                                        z: 2

                                        // Prev Button (36x36 hit target)
                                        Item {
                                            width: 36
                                            height: 36
                                            Layout.alignment: Qt.AlignVCenter

                                            Rectangle {
                                                width: 30
                                                height: 30
                                                radius: 15
                                                anchors.centerIn: parent
                                                color: prevIosM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰒮"
                                                color: prevIosM.containsMouse ? "#ffffff" : root.theme.textSecondary
                                                font.pixelSize: 16
                                                font.family: root.font
                                            }

                                            MouseArea {
                                                id: prevIosM
                                                anchors.fill: parent
                                                enabled: !!root.activePlayer
                                                hoverEnabled: !!root.activePlayer
                                                cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.activePlayer?.previous()
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Play / Pause Circle Button (iOS Style, 38x38)
                                        Rectangle {
                                            width: 38
                                            height: 38
                                            radius: 19
                                            color: playIosM.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : (root.isMediaPlaying ? root.playerAccent : Qt.rgba(1, 1, 1, 0.15))
                                            Layout.alignment: Qt.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: root.isMediaPlaying ? 0 : 1
                                                text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                                color: "#ffffff"
                                                font.pixelSize: 18
                                                font.family: root.font
                                            }

                                            MouseArea {
                                                id: playIosM
                                                anchors.fill: parent
                                                enabled: !!root.activePlayer
                                                hoverEnabled: !!root.activePlayer
                                                cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.activePlayer?.togglePlaying()
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Next Button (36x36 hit target)
                                        Item {
                                            width: 36
                                            height: 36
                                            Layout.alignment: Qt.AlignVCenter

                                            Rectangle {
                                                width: 30
                                                height: 30
                                                radius: 15
                                                anchors.centerIn: parent
                                                color: nextIosM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰒭"
                                                color: nextIosM.containsMouse ? "#ffffff" : root.theme.textSecondary
                                                font.pixelSize: 16
                                                font.family: root.font
                                            }

                                            MouseArea {
                                                id: nextIosM
                                                anchors.fill: parent
                                                enabled: !!root.activePlayer
                                                hoverEnabled: !!root.activePlayer
                                                cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.activePlayer?.next()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // 2. FOCUS, NIGHT SHIFT & CAFFEINE ROW
                        // ═══════════════════════════════════════════
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: card.isCompact ? 6 : 8

                            // 1. Focus / DND Tile
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: focusMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.NotificationService.dnd ? Qt.rgba(root.theme.accentMauve.r, root.theme.accentMauve.g, root.theme.accentMauve.b, 0.45) : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Services.NotificationService.dnd ? root.theme.accentMauve : Qt.rgba(1, 1, 1, 0.08)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.NotificationService.dnd ? "󰂛" : "󰍡"
                                            color: Services.NotificationService.dnd ? "#ffffff" : root.theme.textSecondary
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Focus"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.NotificationService.dnd ? "On" : "Off"
                                            color: Services.NotificationService.dnd ? root.theme.accentMauve : root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: focusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.NotificationService.toggleDnd()
                                }
                            }

                            // 2. Night Shift Tile
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: nightShiftMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.NightLightService.active ? Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.45) : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Services.NightLightService.active ? root.theme.accentOrange : Qt.rgba(1, 1, 1, 0.08)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰔎"
                                            color: Services.NightLightService.active ? "#ffffff" : root.theme.textSecondary
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Night Shift"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.NightLightService.active ? "3000K" : "Off"
                                            color: Services.NightLightService.active ? root.theme.accentOrange : root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: nightShiftMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.NightLightService.toggle()
                                }
                            }

                            // 3. Caffeine Tile
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: caffeineMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.SystemService.caffeineActive ? Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.45) : (Services.SystemService.idleInhibited ? Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.3) : Services.Aesthetic.innerCardBorder)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Services.SystemService.caffeineActive ? root.theme.accentYellow : (Services.SystemService.idleInhibited ? Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.25) : Qt.rgba(1, 1, 1, 0.08))
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅶"
                                            color: Services.SystemService.caffeineActive ? "#000000" : (Services.SystemService.idleInhibited ? root.theme.accentYellow : root.theme.textSecondary)
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Caffeine"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.SystemService.caffeineActive ? "Active" : (Services.SystemService.idleInhibited ? "Auto (Fullscreen)" : "Off")
                                            color: Services.SystemService.idleInhibited ? "#ffb340" : root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: caffeineMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.toggleCaffeine()
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // 3. DISPLAY BRIGHTNESS SLIDER
                        // ═══════════════════════════════════════════
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: card.isCompact ? 72 : 82
                            radius: 16
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: card.isCompact ? 8 : 12
                                spacing: card.isCompact ? 6 : 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Display"
                                        color: root.theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Services.SystemService.brightness + "%"
                                        color: root.theme.textMuted
                                        font.pixelSize: 12
                                        font.family: root.font
                                    }
                                    // Displays Detail Page Chevron Button
                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: dispOpenBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                        opacity: dispOpenBtnM.containsMouse ? 1.0 : 0.65
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "›"
                                            color: root.theme.textMuted
                                            font.pixelSize: 14
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: dispOpenBtnM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.rescanMonitors();
                                                Services.SystemService.controlCenterSubView = "displays";
                                            }
                                        }
                                    }
                                }

                                // Modern macOS Tahoe Capsule Slider Track
                                Rectangle {
                                    id: brightBar
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 16
                                    color: Services.Aesthetic.sliderTrackBg
                                    border.color: brightMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1
                                    clip: true
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    // Background Unfilled Glyph (visible when fill is behind it)
                                    Text {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Services.SystemService.brightness <= 33 ? "󰃞" : (Services.SystemService.brightness <= 66 ? "󰃟" : "󰃠")
                                        color: Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }

                                    // Dynamic Filled Capsule (with dual-layer clipped dark glyph)
                                    Rectangle {
                                        id: brightFill
                                        width: Services.SystemService.brightness <= 0 ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.brightness / 100)))
                                        height: parent.height
                                        radius: 16
                                        color: root.theme.accent
                                        clip: true
                                        Behavior on width {
                                            enabled: !brightMouse.pressed
                                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                        }

                                        // Foreground Dark Glyph (uncovered smoothly as fill expands)
                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.brightness <= 33 ? "󰃞" : (Services.SystemService.brightness <= 66 ? "󰃟" : "󰃠")
                                            color: root.theme.onPrimary
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    MouseArea {
                                        id: brightMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        function applyBrightness(mouseX) {
                                            const rawPct = (mouseX / brightBar.width) * 100;
                                            const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                            Services.SystemService.setBrightnessPercent(pct);
                                        }

                                        onPressed: (mouse) => {
                                            Services.SystemService.isBrightnessDragging = true;
                                            applyBrightness(mouse.x);
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (pressed) {
                                                Services.SystemService.isBrightnessDragging = true;
                                                applyBrightness(mouse.x);
                                            }
                                        }
                                        onReleased: (mouse) => {
                                            applyBrightness(mouse.x);
                                            Services.SystemService.flushBrightness();
                                            Services.SystemService.isBrightnessDragging = false;
                                        }
                                        onCanceled: {
                                            Services.SystemService.flushBrightness();
                                            Services.SystemService.isBrightnessDragging = false;
                                        }
                                        onWheel: (wheel) => {
                                            wheel.accepted = true;
                                            const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                            Services.SystemService.adjustBrightness(delta);
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // 4. SOUND VOLUME SLIDER (CLICK CHEVRON FOR AUDIO PAGE)
                        // ═══════════════════════════════════════════
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: card.isCompact ? 72 : 82
                            radius: 16
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: card.isCompact ? 8 : 12
                                spacing: card.isCompact ? 6 : 8

                                // ── Sound Output Header ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Sound"
                                        color: root.theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Services.SystemService.volumeMuted ? "Muted" : Services.SystemService.volume + "%"
                                        color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.textMuted
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Services.SystemService.volumeMuted ? Font.DemiBold : Font.Normal
                                    }
                                    // Audio Detail Page Chevron Button
                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: soundOpenBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                        opacity: soundOpenBtnM.containsMouse ? 1.0 : 0.65
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "›"
                                            color: root.theme.textMuted
                                            font.pixelSize: 14
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: soundOpenBtnM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.rescanAudioSinks();
                                                Services.SystemService.rescanAudioSources();
                                                Services.SystemService.controlCenterSubView = "audio";
                                            }
                                        }
                                    }
                                }

                                // Modern macOS Tahoe Capsule Sound Slider Track
                                Rectangle {
                                    id: soundBar
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 16
                                    color: Services.SystemService.volumeMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                    border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (soundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06))
                                    border.width: 1
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    // Background Unfilled Glyph
                                    Text {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Services.SystemService.volumeIcon
                                        color: Services.SystemService.volumeMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }

                                    // Dynamic Filled Capsule (with dual-layer clipped dark glyph)
                                    Rectangle {
                                        id: soundFill
                                        width: (Services.SystemService.volumeMuted || Services.SystemService.volume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))
                                        height: parent.height
                                        radius: 16
                                        color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.accent
                                        clip: true
                                        Behavior on width {
                                            enabled: !soundMouse.pressed
                                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                        }

                                        // Foreground Glyph
                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.volumeIcon
                                            color: Services.SystemService.volumeMuted ? "#ffffff" : root.theme.onPrimary
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    MouseArea {
                                        id: soundMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        property real startX: 0
                                        property real startY: 0
                                        property bool isDragging: false
                                        property bool startedInIcon: false

                                        function applyVolume(mouseX) {
                                            const rawPct = (mouseX / soundBar.width) * 100;
                                            const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                            Services.SystemService.setVolumePercent(pct);
                                        }

                                        onPressed: (mouse) => {
                                            startX = mouse.x;
                                            startY = mouse.y;
                                            isDragging = false;
                                            startedInIcon = (mouse.x <= 36);
                                            if (!startedInIcon) {
                                                isDragging = true;
                                                Services.SystemService.isVolumeDragging = true;
                                                applyVolume(mouse.x);
                                            }
                                        }

                                        onPositionChanged: (mouse) => {
                                            if (pressed) {
                                                const dx = Math.abs(mouse.x - startX);
                                                if (!isDragging && (dx > 4 || mouse.x > 36)) {
                                                    isDragging = true;
                                                    startedInIcon = false;
                                                    Services.SystemService.isVolumeDragging = true;
                                                }
                                                if (isDragging) {
                                                    applyVolume(mouse.x);
                                                }
                                            }
                                        }

                                        onReleased: (mouse) => {
                                            if (isDragging) {
                                                applyVolume(mouse.x);
                                                Services.SystemService.flushVolume();
                                                Services.SystemService.isVolumeDragging = false;
                                                isDragging = false;
                                            } else if (startedInIcon && Math.abs(mouse.x - startX) <= 4) {
                                                Services.SystemService.toggleMute();
                                            }
                                            startedInIcon = false;
                                        }

                                        onCanceled: {
                                            isDragging = false;
                                            startedInIcon = false;
                                            Services.SystemService.flushVolume();
                                            Services.SystemService.isVolumeDragging = false;
                                        }

                                        onWheel: (wheel) => {
                                            wheel.accepted = true;
                                            const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                            Services.SystemService.adjustVolume(delta);
                                        }
                                    }
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // 5. QUICK TILES: CAPTURE, POWER PROFILE & POWER MENU
                        // ═══════════════════════════════════════════
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: card.isCompact ? 6 : 8

                            // 1. Screen Capture Tile (opens floating screenshot module)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: snapTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 6 : 8
                                    spacing: card.isCompact ? 6 : 8

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰹑"
                                            color: root.theme.accent
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Capture"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Screenshot"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: snapTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.ScreenshotService.openToolbar();
                                    }
                                }
                            }

                            // 2. Power Menu Tile
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: powerMenuTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 6 : 8
                                    spacing: card.isCompact ? 6 : 8

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.16)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰐥"
                                            color: root.theme.accentRed
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Power"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Menu"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: powerMenuTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.togglePowerMenu()
                                }
                            }
                        }
                        // ═══════════════════════════════════════════
                        // 6. BOTTOM STATUS CAPSULE: BATTERY & SYSTEM STATS
                        // ═══════════════════════════════════════════
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: card.isCompact ? 6 : 8

                            // Battery Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: battTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 6 : 8
                                    spacing: card.isCompact ? 6 : 8

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(1, 1, 1, 0.08)

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.SystemService.batteryIcon
                                            color: (Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged) ? root.theme.battGood
                                                 : Services.SystemService.batteryLevel > 30 ? root.theme.battGood : root.theme.battWarn
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: Services.SystemService.batteryLevel + "%" + ((Services.SystemService.batteryPlugged || Services.SystemService.batteryCharging) ? " 󱐋" : "")
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.SystemService.batteryCharging ? "Charging" : (Services.SystemService.batteryPlugged ? "AC Connected" : "Battery")
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: "›"
                                        color: root.theme.textMuted
                                        opacity: battTileMouse.containsMouse ? 0.9 : 0.45
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        font.pixelSize: 16
                                        font.family: root.font
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: battTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.controlCenterSubView = "battery"
                                }
                            }

                            // Displays & Monitor Management Tile (Opens Displays Subview)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: card.isCompact ? 46 : 52
                                radius: 14
                                color: dispTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: card.isCompact ? 6 : 8
                                    spacing: card.isCompact ? 6 : 8

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰍹"
                                            color: root.theme.accent
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.name + " • " + Math.round(Services.SystemService.monitorScale * 100) + "% scale") : "Displays"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Displays & Scaling"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: "›"
                                        color: root.theme.textMuted
                                        opacity: dispTileMouse.containsMouse ? 0.9 : 0.45
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        font.pixelSize: 16
                                        font.family: root.font
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: dispTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.SystemService.rescanMonitors();
                                        Services.SystemService.controlCenterSubView = "displays";
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 2: macOS STYLE NATIVE WI-FI DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: wifiDetailsView
                    visible: root.activeView === "wifi"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back button with generous hit area & hover scale
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: backWM.pressed ? Services.Aesthetic.innerCardHover : (backWM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg)
                            border.color: backWM.containsMouse ? root.theme.outline : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: backWM.pressed ? 0.92 : (backWM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: backWM.containsMouse ? root.theme.textPrimary : root.theme.textSecondary
                                font.pixelSize: 18
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }
                            MouseArea {
                                id: backWM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.wifiPromptSsid !== "") {
                                        root.wifiPromptSsid = "";
                                        root.wifiPasswordText = "";
                                        Services.SystemService.wifiConnectError = "";
                                    } else if (root.wifiJoinOtherMode) {
                                        root.wifiJoinOtherMode = false;
                                        root.wifiOtherSsid = "";
                                        root.wifiOtherPassword = "";
                                        Services.SystemService.wifiConnectError = "";
                                    } else {
                                        root.wifiShowOtherNetworkModal = false;
                                        Services.SystemService.controlCenterSubView = "main";
                                    }
                                }
                            }
                        }

                        Text {
                            text: root.wifiPromptSsid !== "" ? "Join Network" : (root.wifiJoinOtherMode ? "Join Other Network" : "Wi-Fi")
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }

                        Item { Layout.fillWidth: true }

                        // Rescan button with rotation & scale
                        Rectangle {
                            id: rescBtn
                            width: 30
                            height: 30
                            radius: 15
                            visible: Services.SystemService.wifiEnabled && root.wifiPromptSsid === "" && !root.wifiJoinOtherMode
                            color: rescWM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (rescWM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15) : Services.Aesthetic.innerCardBg)
                            border.color: rescWM.containsMouse ? root.theme.accent : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: rescWM.pressed ? 0.90 : (rescWM.containsMouse ? 1.08 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: Services.SystemService.wifiScanning ? root.theme.accent : (rescWM.containsMouse ? root.theme.textPrimary : root.theme.accent)
                                font.pixelSize: 13
                                font.family: root.font
                                transformOrigin: Item.Center

                                NumberAnimation on rotation {
                                    running: Services.SystemService.wifiScanning
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                }
                            }

                            ToolTip.visible: rescWM.containsMouse
                            ToolTip.text: "Scan for Networks"
                            ToolTip.delay: 400

                            MouseArea {
                                id: rescWM
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.rescanWifi()
                            }
                        }

                        // Power switch
                        Rectangle {
                            width: 44
                            height: 24
                            radius: 12
                            visible: Services.SystemService.wifiEnabled && root.wifiPromptSsid === "" && !root.wifiJoinOtherMode
                            color: Services.SystemService.wifiEnabled ? (pwrWifiSwMouse.containsMouse ? Qt.lighter(root.theme.accent, 1.1) : root.theme.accent) : (pwrWifiSwMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg)
                            border.color: Services.SystemService.wifiEnabled ? root.theme.accent : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: pwrWifiSwMouse.pressed ? 0.94 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: Services.SystemService.wifiEnabled ? root.theme.onPrimary : root.theme.textPrimary
                                anchors.verticalCenter: parent.verticalCenter
                                x: Services.SystemService.wifiEnabled ? 22 : 2
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: pwrWifiSwMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.toggleWifi()
                            }
                        }
                    }

                    // ── OFF STATE PLACEHOLDER ─────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !Services.SystemService.wifiEnabled

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 56
                                height: 56
                                radius: 28
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰖪"
                                    color: root.theme.textMuted
                                    font.pixelSize: 26
                                    font.family: root.font
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Wi-Fi is Off"
                                color: root.theme.textPrimary
                                font.pixelSize: 14
                                font.family: root.font
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Turn on Wi-Fi to find and connect to local wireless networks."
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 96
                                height: 32
                                radius: 16
                                color: turnOnWifiM.pressed ? Qt.darker(root.theme.accent, 1.15) : (turnOnWifiM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)
                                scale: turnOnWifiM.pressed ? 0.94 : (turnOnWifiM.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Turn On"
                                    color: root.theme.onPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: turnOnWifiM
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.toggleWifi()
                                }
                            }
                        }
                    }

                    // ── ON STATE: SCROLLABLE NETWORKS LIST ─────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        visible: Services.SystemService.wifiEnabled && root.wifiPromptSsid === "" && !root.wifiJoinOtherMode
                        contentWidth: width
                        contentHeight: wifiContentCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiContentCol
                            width: parent.width
                            Layout.fillWidth: true
                            Layout.preferredWidth: parent.width
                            Layout.maximumWidth: parent.width
                            spacing: 14

                            // ── CONNECTED CARD (ACCENT-TINTED) ───────────────
                            Rectangle {
                                Layout.fillWidth: true
                                width: wifiContentCol.width
                                implicitHeight: activeNetCol.implicitHeight + 20
                                radius: 14
                                clip: true
                                visible: Services.SystemService.wifiConnected && Services.SystemService.wifiActiveNetwork !== null
                                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                                border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28)
                                border.width: 1

                                ColumnLayout {
                                    id: activeNetCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // Top Section: Icon + Network Info + Disconnect Button
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        // Network Icon (left)
                                        Rectangle {
                                            width: 36
                                            height: 36
                                            radius: 18
                                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)

                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                color: root.theme.accent
                                                font.pixelSize: 16
                                                font.family: root.font
                                            }
                                        }

                                        // Center info column
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.ssid || Services.SystemService.wifiSsid) : Services.SystemService.wifiSsid
                                                color: root.theme.textPrimary
                                                font.pixelSize: 13
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: "Connected"
                                                    + (Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.band ? (" · " + Services.SystemService.wifiActiveNetwork.band) : "")
                                                    + (Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.security ? (" · " + Services.SystemService.wifiActiveNetwork.security) : "")
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        // Disconnect Pill Button
                                        Rectangle {
                                            id: actDisconBtn
                                            width: disconTxt.implicitWidth + 16
                                            height: 24
                                            radius: 12
                                            color: disconWM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.18) : Services.Aesthetic.innerCardBg
                                            border.color: disconWM.containsMouse ? root.theme.accentRed : Services.Aesthetic.innerCardBorder
                                            border.width: 1
                                            scale: disconWM.pressed ? 0.94 : (disconWM.containsMouse ? 1.04 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            Text {
                                                id: disconTxt
                                                anchors.centerIn: parent
                                                text: "Disconnect"
                                                color: disconWM.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: disconWM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.disconnectWifi()
                                            }
                                        }
                                    }

                                    // Divider line
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15)
                                    }

                                    // Details toggle header
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: 20

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 6

                                            Text {
                                                text: "Details"
                                                color: dtMouse.containsMouse ? root.theme.textPrimary : root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.Medium
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "⌄"
                                                color: dtMouse.containsMouse ? root.theme.textPrimary : root.theme.textMuted
                                                font.pixelSize: 12
                                                font.family: root.font
                                                rotation: root.wifiShowActiveDetails ? 180 : 0
                                                transformOrigin: Item.Center
                                                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        MouseArea {
                                            id: dtMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.wifiShowActiveDetails = !root.wifiShowActiveDetails
                                        }
                                    }

                                    // Expandable Animated Details Section
                                    Item {
                                        Layout.fillWidth: true
                                        clip: true
                                        Layout.preferredHeight: root.wifiShowActiveDetails ? actDetailsCol.implicitHeight : 0
                                        implicitHeight: Layout.preferredHeight
                                        visible: root.wifiShowActiveDetails || Layout.preferredHeight > 0
                                        opacity: root.wifiShowActiveDetails ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        ColumnLayout {
                                            id: actDetailsCol
                                            width: parent.width
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Signal:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: (Services.SystemService.wifiActiveNetwork ? Services.SystemService.wifiActiveNetwork.signal : 0) + "%"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Speed:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Row {
                                                    spacing: 6
                                                    Text {
                                                        text: "↓ " + Services.SystemService.wifiRxFormatted
                                                        color: root.theme.textPrimary
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                        font.features: { "tnum": 1 }
                                                        width: 64
                                                        horizontalAlignment: Text.AlignRight
                                                    }
                                                    Text { text: "·"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                    Text {
                                                        text: "↑ " + Services.SystemService.wifiTxFormatted
                                                        color: root.theme.textPrimary
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                        font.features: { "tnum": 1 }
                                                        width: 64
                                                        horizontalAlignment: Text.AlignRight
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "IP Address:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork ? Services.SystemService.wifiActiveNetwork.ip : "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Gateway:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.gateway || "--") : "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "DNS:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.dns || "--") : "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font; elide: Text.ElideLeft; Layout.maximumWidth: 160 }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "BSSID (MAC):"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.bssid || "--") : "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: !!(Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.rate)
                                                Text { text: "Link Speed:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.rate || "--") : "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            // Forget this network button
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 28
                                                radius: 8
                                                color: fgtActiveM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.15) : Services.Aesthetic.innerCardBg
                                                border.color: fgtActiveM.containsMouse ? root.theme.accentRed : Services.Aesthetic.innerCardBorder
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: "󰆴"; color: root.theme.accentRed; font.pixelSize: 11; font.family: root.font; anchors.verticalCenter: parent.verticalCenter }
                                                    Text { text: "Forget This Network"; color: root.theme.accentRed; font.pixelSize: 10; font.family: root.font; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                                                }

                                                MouseArea {
                                                    id: fgtActiveM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.SystemService.wifiActiveNetwork) {
                                                            Services.SystemService.forgetWifi(Services.SystemService.wifiActiveNetwork.ssid);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── KNOWN NETWORKS SECTION ────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: Services.SystemService.wifiKnownNetworks.length > 0

                                Text {
                                    text: "KNOWN NETWORKS"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 2
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: knownCol.implicitHeight
                                    radius: 12
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    clip: true

                                    ColumnLayout {
                                        id: knownCol
                                        width: parent.width
                                        spacing: 0

                                        Repeater {
                                            model: Services.SystemService.wifiKnownNetworks

                                            delegate: ColumnLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 0

                                                // Hairline divider
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Services.Aesthetic.innerCardBorder
                                                    visible: index > 0
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 44
                                                    color: knownRowM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    MouseArea {
                                                        id: knownRowM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Services.SystemService.connectWifi(modelData.ssid)
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 10

                                                        // Neutral Circle Icon
                                                        Rectangle {
                                                            width: 28
                                                            height: 28
                                                            radius: 14
                                                            color: Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.08)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: ""
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            Text {
                                                                text: modelData.ssid
                                                                color: root.theme.textPrimary
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }

                                                            Text {
                                                                text: (modelData.is_locked ? "󰌾 " : "") + (modelData.security || "Secured") + (modelData.band ? (" · " + modelData.band) : "")
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                            }
                                                        }

                                                        // Forget icon button (visible on hover)
                                                        Rectangle {
                                                            width: 24
                                                            height: 24
                                                            radius: 6
                                                            visible: knownRowM.containsMouse || fgtKnownM.containsMouse
                                                            color: fgtKnownM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.15) : "transparent"
                                                            Behavior on color { ColorAnimation { duration: 100 } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰆴"
                                                                color: fgtKnownM.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                            }

                                                            MouseArea {
                                                                id: fgtKnownM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Services.SystemService.forgetWifi(modelData.ssid)
                                                            }
                                                        }

                                                        // Tonal Accent Connect pill
                                                        Rectangle {
                                                            id: connBtnKnown
                                                            height: 24
                                                            implicitWidth: isThisConnecting ? 76 : (connKnownTxt.implicitWidth + 16)
                                                            radius: 12
                                                            readonly property bool isThisConnecting: Services.SystemService.wifiConnecting && Services.SystemService.wifiConnectingSsid === modelData.ssid
                                                            color: isThisConnecting ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28) : (connKnownM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12))
                                                            border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                                            border.width: 1
                                                            scale: connKnownM.pressed ? 0.94 : (connKnownM.containsMouse ? 1.04 : 1.0)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                                            Row {
                                                                anchors.centerIn: parent
                                                                spacing: 4
                                                                Text {
                                                                    text: "󰑐"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 10
                                                                    font.family: root.font
                                                                    visible: connBtnKnown.isThisConnecting
                                                                    transformOrigin: Item.Center
                                                                    NumberAnimation on rotation {
                                                                        running: connBtnKnown.isThisConnecting
                                                                        loops: Animation.Infinite
                                                                        from: 0
                                                                        to: 360
                                                                        duration: 800
                                                                    }
                                                                }
                                                                Text {
                                                                    id: connKnownTxt
                                                                    text: connBtnKnown.isThisConnecting ? "Joining…" : "Connect"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 10
                                                                    font.family: root.font
                                                                    font.weight: Font.Medium
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: connKnownM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Services.SystemService.connectWifi(modelData.ssid)
                                                            }
                                                        }

                                                        // Signal icon
                                                        Text {
                                                            text: root.getWifiSignalIcon(modelData.signal)
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 13
                                                            font.family: root.font
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── OTHER NETWORKS SECTION ────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "OTHER NETWORKS"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 2
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: otherCol.implicitHeight
                                    radius: 12
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    clip: true

                                    ColumnLayout {
                                        id: otherCol
                                        width: parent.width
                                        spacing: 0

                                        // Empty Placeholder (single muted line)
                                        Item {
                                            Layout.fillWidth: true
                                            height: 38
                                            visible: Services.SystemService.wifiOtherNetworks.length === 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.SystemService.wifiScanning ? "Scanning for networks…" : "No other networks found"
                                                color: root.theme.textMuted
                                                font.pixelSize: 11
                                                font.family: root.font
                                            }
                                        }

                                        Repeater {
                                            model: Services.SystemService.wifiOtherNetworks

                                            delegate: ColumnLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 0

                                                readonly property bool isThisConnecting: Services.SystemService.wifiConnecting && Services.SystemService.wifiConnectingSsid === modelData.ssid

                                                // Hairline divider between rows
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Services.Aesthetic.innerCardBorder
                                                    visible: index > 0
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 44
                                                    color: otherRowM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    MouseArea {
                                                        id: otherRowM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (!modelData.is_locked) {
                                                                Services.SystemService.connectWifi(modelData.ssid);
                                                            } else {
                                                                root.wifiPromptSsid = modelData.ssid;
                                                                root.wifiPasswordText = "";
                                                                root.wifiShowPasswordText = false;
                                                                Services.SystemService.wifiConnectError = "";
                                                            }
                                                        }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 10

                                                        // Neutral Circle Icon
                                                        Rectangle {
                                                            width: 28
                                                            height: 28
                                                            radius: 14
                                                            color: Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.08)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: ""
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            Text {
                                                                text: modelData.ssid
                                                                color: root.theme.textPrimary
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }

                                                            Text {
                                                                text: (modelData.is_locked ? "󰌾 " : "") + (modelData.security || "Open") + (modelData.band ? (" · " + modelData.band) : "")
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                            }
                                                        }

                                                        // Connecting Pill Indicator
                                                        Rectangle {
                                                            height: 24
                                                            implicitWidth: 76
                                                            radius: 12
                                                            visible: isThisConnecting
                                                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28)
                                                            border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                                            border.width: 1

                                                            Row {
                                                                anchors.centerIn: parent
                                                                spacing: 4
                                                                Text {
                                                                    text: "󰑐"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 10
                                                                    font.family: root.font
                                                                    transformOrigin: Item.Center
                                                                    NumberAnimation on rotation {
                                                                        running: isThisConnecting
                                                                        loops: Animation.Infinite
                                                                        from: 0
                                                                        to: 360
                                                                        duration: 800
                                                                    }
                                                                }
                                                                Text {
                                                                    text: "Joining…"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 10
                                                                    font.family: root.font
                                                                    font.weight: Font.Medium
                                                                }
                                                            }
                                                        }

                                                        // Signal icon
                                                        Text {
                                                            text: root.getWifiSignalIcon(modelData.signal)
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 13
                                                            font.family: root.font
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Hairline divider before Join Other Network
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Services.Aesthetic.innerCardBorder
                                        }

                                        // ── JOIN OTHER NETWORK (LAST ROW IN GROUP) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 44
                                            color: joinOtherM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                            Behavior on color { ColorAnimation { duration: 100 } }

                                            MouseArea {
                                                id: joinOtherM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.wifiJoinOtherMode = true;
                                                    root.wifiOtherSsid = "";
                                                    root.wifiOtherPassword = "";
                                                    root.wifiShowPasswordText = false;
                                                    Services.SystemService.wifiConnectError = "";
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Rectangle {
                                                    width: 28
                                                    height: 28
                                                    radius: 14
                                                    color: Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.08)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󱛄"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 13
                                                        font.family: root.font
                                                    }
                                                }

                                                Text {
                                                    text: "Join Other Network…"
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    font.weight: Font.Medium
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: "›"
                                                    color: root.theme.textMuted
                                                    font.pixelSize: 16
                                                    font.family: root.font
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // ── DEDICATED ANDROID / iOS STYLE ENTER PASSWORD SCREEN ──
                    ColumnLayout {
                        id: wifiPasswordView
                        Layout.fillWidth: true
                        visible: Services.SystemService.wifiEnabled && root.wifiPromptSsid !== ""
                        spacing: 14

                        Timer {
                            interval: 60
                            running: root.activeView === "wifi" && root.wifiPromptSsid !== ""
                            onTriggered: dedicatedWifiPassInput.forceActiveFocus()
                        }

                        // 1. Target Network Hero Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: promptHeroCol.implicitHeight + 22
                            radius: 14
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1

                            RowLayout {
                                id: promptHeroCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 42
                                    height: 42
                                    radius: 12
                                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                                    border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.getWifiSignalIcon(root.targetPromptNetwork ? root.targetPromptNetwork.signal : 70)
                                        color: root.theme.accent
                                        font.pixelSize: 20
                                        font.family: root.font
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: root.wifiPromptSsid
                                        color: root.theme.textPrimary
                                        font.pixelSize: 15
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        spacing: 6
                                        Text {
                                            text: "󰌾"
                                            color: root.theme.accent
                                            font.pixelSize: 10
                                            font.family: root.font
                                        }
                                        Text {
                                            text: (root.targetPromptNetwork?.security || "WPA/WPA2 Personal") + " • " + (root.targetPromptNetwork?.band || "2.4 GHz")
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Password Input Field
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "PASSWORD"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: Font.DemiBold
                                Layout.leftMargin: 2
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 42
                                radius: 12
                                color: Services.Aesthetic.innerCardBg
                                border.color: dedicatedWifiPassInput.activeFocus ? root.theme.accent : Services.Aesthetic.innerCardBorder
                                border.width: 1

                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: "󰌆"
                                        color: dedicatedWifiPassInput.activeFocus ? root.theme.accent : root.theme.textMuted
                                        font.pixelSize: 14
                                        font.family: root.font
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    TextInput {
                                        id: dedicatedWifiPassInput
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: root.font
                                        echoMode: root.wifiShowPasswordText ? TextInput.Normal : TextInput.Password
                                        text: root.wifiPasswordText
                                        onTextChanged: root.wifiPasswordText = text

                                        function submitJoin() {
                                            if (text.length > 0 && !Services.SystemService.wifiConnecting) {
                                                Services.SystemService.connectWifiWithPassword(root.wifiPromptSsid, text);
                                            }
                                        }

                                        Keys.onReturnPressed: submitJoin()

                                        Text {
                                            anchors.fill: parent
                                            text: "Enter Password"
                                            color: Qt.rgba(1, 1, 1, 0.35)
                                            font: parent.font
                                            visible: !parent.text && !parent.activeFocus
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    // Eye toggle
                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 7
                                        color: eyeDedicatedM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.wifiShowPasswordText ? "󰈈" : "󰈉"
                                            color: root.wifiShowPasswordText ? root.theme.accent : root.theme.textMuted
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: eyeDedicatedM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.wifiShowPasswordText = !root.wifiShowPasswordText
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Error Banner
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: errDedicatedRow.implicitHeight + 12
                            radius: 10
                            color: Qt.rgba(1, 0.27, 0.23, 0.15)
                            border.color: Qt.rgba(1, 0.27, 0.23, 0.35)
                            border.width: 1
                            visible: !!Services.SystemService.wifiConnectError

                            RowLayout {
                                id: errDedicatedRow
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Text { text: "󰅚"; color: "#ff453a"; font.pixelSize: 14; font.family: root.font }
                                Text {
                                    text: Services.SystemService.wifiConnectError
                                    color: "#ff453a"
                                    font.pixelSize: 11
                                    font.family: root.font
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // 4. Action Buttons (Cancel & Join)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                height: 38
                                radius: 12
                                color: cancelDedicatedM.pressed ? Qt.rgba(1, 1, 1, 0.16) : (cancelDedicatedM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                border.color: cancelDedicatedM.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                scale: cancelDedicatedM.pressed ? 0.96 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: cancelDedicatedM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.wifiPromptSsid = "";
                                        root.wifiPasswordText = "";
                                        Services.SystemService.wifiConnectError = "";
                                    }
                                }
                            }

                            Rectangle {
                                id: joinDedicatedBtn
                                Layout.fillWidth: true
                                height: 38
                                radius: 12
                                readonly property bool canJoin: root.wifiPasswordText.length > 0 && !Services.SystemService.wifiConnecting
                                color: canJoin ? (joinDedicatedM.pressed ? Qt.darker(root.theme.accent, 1.15) : (joinDedicatedM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                scale: canJoin && joinDedicatedM.pressed ? 0.96 : (canJoin && joinDedicatedM.containsMouse ? 1.02 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "󰑐"
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: root.font
                                        visible: Services.SystemService.wifiConnecting
                                        transformOrigin: Item.Center
                                        NumberAnimation on rotation {
                                            running: Services.SystemService.wifiConnecting
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 360
                                            duration: 800
                                        }
                                    }

                                    Text {
                                        text: Services.SystemService.wifiConnecting ? "Joining..." : "Join"
                                        color: parent.parent.canJoin || Services.SystemService.wifiConnecting ? "#ffffff" : Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: joinDedicatedM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: parent.canJoin ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (parent.canJoin) {
                                            Services.SystemService.connectWifiWithPassword(root.wifiPromptSsid, root.wifiPasswordText);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── DEDICATED ANDROID / iOS STYLE JOIN OTHER NETWORK SCREEN ──
                    ColumnLayout {
                        id: wifiJoinOtherView
                        Layout.fillWidth: true
                        visible: Services.SystemService.wifiEnabled && root.wifiJoinOtherMode && root.wifiPromptSsid === ""
                        spacing: 14

                        Timer {
                            interval: 80
                            running: root.activeView === "wifi" && root.wifiJoinOtherMode && root.wifiPromptSsid === ""
                            onTriggered: dedicatedOtherSsidInput.forceActiveFocus()
                        }

                        // 1. Hero Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: otherHeroCol.implicitHeight + 22
                            radius: 14
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1

                            RowLayout {
                                id: otherHeroCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 42
                                    height: 42
                                    radius: 12
                                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                                    border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󱛄"
                                        color: root.theme.accent
                                        font.pixelSize: 20
                                        font.family: root.font
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: "Other Network"
                                        color: root.theme.textPrimary
                                        font.pixelSize: 15
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "Enter name and security settings"
                                        color: root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                    }
                                }
                            }
                        }

                        // 2. Network Name (SSID) Input Field
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "NETWORK NAME"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: Font.DemiBold
                                Layout.leftMargin: 2
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 42
                                radius: 12
                                color: Services.Aesthetic.innerCardBg
                                border.color: dedicatedOtherSsidInput.activeFocus ? root.theme.accent : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: ""
                                        color: dedicatedOtherSsidInput.activeFocus ? root.theme.accent : root.theme.textMuted
                                        font.pixelSize: 14
                                        font.family: root.font
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    TextInput {
                                        id: dedicatedOtherSsidInput
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: root.font
                                        text: root.wifiOtherSsid
                                        onTextChanged: root.wifiOtherSsid = text

                                        Keys.onReturnPressed: {
                                            if (root.wifiOtherSsid.trim().length > 0) {
                                                dedicatedOtherPassInput.forceActiveFocus();
                                            }
                                        }

                                        Text {
                                            anchors.fill: parent
                                            text: "Enter Network Name (SSID)"
                                            color: Qt.rgba(1, 1, 1, 0.35)
                                            font: parent.font
                                            visible: !parent.text && !parent.activeFocus
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Password Input Field
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "PASSWORD (OPTIONAL FOR OPEN)"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: Font.DemiBold
                                Layout.leftMargin: 2
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 42
                                radius: 12
                                color: Services.Aesthetic.innerCardBg
                                border.color: dedicatedOtherPassInput.activeFocus ? root.theme.accent : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: "󰌆"
                                        color: dedicatedOtherPassInput.activeFocus ? root.theme.accent : root.theme.textMuted
                                        font.pixelSize: 14
                                        font.family: root.font
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    TextInput {
                                        id: dedicatedOtherPassInput
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: root.font
                                        echoMode: root.wifiShowPasswordText ? TextInput.Normal : TextInput.Password
                                        text: root.wifiOtherPassword
                                        onTextChanged: root.wifiOtherPassword = text

                                        function submitJoinOther() {
                                            if (root.wifiOtherSsid.trim().length > 0 && !Services.SystemService.wifiConnecting) {
                                                Services.SystemService.connectHiddenWifi(root.wifiOtherSsid.trim(), text);
                                            }
                                        }

                                        Keys.onReturnPressed: submitJoinOther()

                                        Text {
                                            anchors.fill: parent
                                            text: "Enter Password"
                                            color: Qt.rgba(1, 1, 1, 0.35)
                                            font: parent.font
                                            visible: !parent.text && !parent.activeFocus
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    // Eye toggle
                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 7
                                        color: eyeOtherM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.wifiShowPasswordText ? "󰈈" : "󰈉"
                                            color: root.wifiShowPasswordText ? root.theme.accent : root.theme.textMuted
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: eyeOtherM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.wifiShowPasswordText = !root.wifiShowPasswordText
                                        }
                                    }
                                }
                            }
                        }

                        // 4. Error Banner
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: errOtherRow.implicitHeight + 12
                            radius: 10
                            color: Qt.rgba(1, 0.27, 0.23, 0.15)
                            border.color: Qt.rgba(1, 0.27, 0.23, 0.35)
                            border.width: 1
                            visible: !!Services.SystemService.wifiConnectError

                            RowLayout {
                                id: errOtherRow
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Text { text: "󰅚"; color: "#ff453a"; font.pixelSize: 14; font.family: root.font }
                                Text {
                                    text: Services.SystemService.wifiConnectError
                                    color: "#ff453a"
                                    font.pixelSize: 11
                                    font.family: root.font
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // 5. Action Buttons (Cancel & Join)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                height: 38
                                radius: 12
                                color: cancelOtherDedicatedM.pressed ? Qt.rgba(1, 1, 1, 0.16) : (cancelOtherDedicatedM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                border.color: cancelOtherDedicatedM.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                scale: cancelOtherDedicatedM.pressed ? 0.96 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: cancelOtherDedicatedM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.wifiJoinOtherMode = false;
                                        root.wifiOtherSsid = "";
                                        root.wifiOtherPassword = "";
                                        Services.SystemService.wifiConnectError = "";
                                    }
                                }
                            }

                            Rectangle {
                                id: joinOtherDedicatedBtn
                                Layout.fillWidth: true
                                height: 38
                                radius: 12
                                readonly property bool canJoin: root.wifiOtherSsid.trim().length > 0 && !Services.SystemService.wifiConnecting
                                color: canJoin ? (joinOtherDedicatedM.pressed ? Qt.darker(root.theme.accent, 1.15) : (joinOtherDedicatedM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                scale: canJoin && joinOtherDedicatedM.pressed ? 0.96 : (canJoin && joinOtherDedicatedM.containsMouse ? 1.02 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "󰑐"
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: root.font
                                        visible: Services.SystemService.wifiConnecting
                                        transformOrigin: Item.Center
                                        NumberAnimation on rotation {
                                            running: Services.SystemService.wifiConnecting
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 360
                                            duration: 800
                                        }
                                    }

                                    Text {
                                        text: Services.SystemService.wifiConnecting ? "Joining..." : "Join"
                                        color: parent.parent.canJoin || Services.SystemService.wifiConnecting ? "#ffffff" : Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: joinOtherDedicatedM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: parent.canJoin ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (parent.canJoin) {
                                            Services.SystemService.connectHiddenWifi(root.wifiOtherSsid.trim(), root.wifiOtherPassword);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 3: BLUETOOTH DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: btDetailsView
                    visible: root.activeView === "bluetooth"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    readonly property var connectedBtDevices: (Services.SystemService.bluetoothDevices || []).filter(d => d.connected)
                    readonly property var pairedBtDevices: (Services.SystemService.bluetoothDevices || []).filter(d => !d.connected)

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back button with generous hit area & hover scale
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: backBM.pressed ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.18) : (backBM.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.12) : Services.Aesthetic.innerCardBg)
                            border.color: backBM.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.25) : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: backBM.pressed ? 0.92 : (backBM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backBM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Bluetooth"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Rescan button with rotation & hover/press scale
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            visible: Services.SystemService.bluetoothEnabled
                            color: rescBM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (rescBM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Services.Aesthetic.innerCardBg)
                            border.color: rescBM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: rescBM.pressed ? 0.90 : (rescBM.containsMouse ? 1.08 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                id: scanIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: Services.SystemService.bluetoothDiscovering ? root.theme.accent : (rescBM.containsMouse ? root.theme.textPrimary : root.theme.accent)
                                font.pixelSize: 13
                                font.family: root.font
                                transformOrigin: Item.Center

                                NumberAnimation on rotation {
                                    running: Services.SystemService.bluetoothDiscovering
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                }
                            }

                            ToolTip.visible: rescBM.containsMouse
                            ToolTip.text: "Scan for Devices"
                            ToolTip.delay: 400

                            MouseArea {
                                id: rescBM
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.rescanBluetooth()
                            }
                        }

                        // Switch with hover track effect & press scale
                        Rectangle {
                            width: 44
                            height: 24
                            radius: 12
                            visible: Services.SystemService.bluetoothEnabled
                            color: Services.SystemService.bluetoothEnabled ? (pwrSwMouse.containsMouse ? Qt.lighter(root.theme.accent, 1.1) : root.theme.accent) : (pwrSwMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg)
                            border.color: Services.SystemService.bluetoothEnabled ? root.theme.accent : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: pwrSwMouse.pressed ? 0.94 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: Services.SystemService.bluetoothEnabled ? root.theme.onPrimary : root.theme.textPrimary
                                anchors.verticalCenter: parent.verticalCenter
                                x: Services.SystemService.bluetoothEnabled ? 22 : 2
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: pwrSwMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.toggleBluetooth()
                            }
                        }
                    }

                    // ── OFF STATE PLACEHOLDER ─────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !Services.SystemService.bluetoothEnabled

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 56
                                height: 56
                                radius: 28
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰂲"
                                    color: root.theme.textMuted
                                    font.pixelSize: 26
                                    font.family: root.font
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Bluetooth is Off"
                                color: root.theme.textPrimary
                                font.pixelSize: 14
                                font.family: root.font
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Turn on Bluetooth to connect accessories & headphones."
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 96
                                height: 32
                                radius: 16
                                color: turnOnBtM.pressed ? Qt.darker(root.theme.accent, 1.15) : (turnOnBtM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)
                                scale: turnOnBtM.pressed ? 0.94 : (turnOnBtM.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Turn On"
                                    color: root.theme.onPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: turnOnBtM
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.toggleBluetooth()
                                }
                            }
                        }
                    }

                    // ── ON STATE: SCROLLABLE DEVICES LIST ─────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        visible: Services.SystemService.bluetoothEnabled
                        contentWidth: width
                        contentHeight: btContentCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: btContentCol
                            width: parent.width
                            Layout.fillWidth: true
                            Layout.preferredWidth: parent.width
                            Layout.maximumWidth: parent.width
                            spacing: 14

                            // ── CONNECTED DEVICES (ACCENT-TINTED) ───────────
                            Repeater {
                                model: btDetailsView.connectedBtDevices

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    radius: 12
                                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                                    border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28)
                                    border.width: 1

                                    MouseArea {
                                        id: connRowM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        // Accent Circle with Device Glyph
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getBtIcon(modelData.icon)
                                                color: root.theme.accent
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        // Name & ONE muted line: "Connected · 80%"
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: modelData.name || modelData.mac
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: "Connected" + (modelData.battery !== null && modelData.battery !== undefined ? (" · " + modelData.battery + "%") : "")
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                            }
                                        }

                                        // Forget / Remove icon button (visible on hover)
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            radius: 6
                                            visible: connRowM.containsMouse || fgtConnM.containsMouse
                                            color: fgtConnM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.15) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 100 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰆴"
                                                color: fgtConnM.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                font.pixelSize: 12
                                                font.family: root.font
                                            }

                                            MouseArea {
                                                id: fgtConnM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.removeBluetooth(modelData.mac)
                                            }
                                        }

                                        // Quiet neutral Disconnect button that turns error-colored on hover
                                        Rectangle {
                                            id: disconBtBtn
                                            height: 24
                                            implicitWidth: disconBtTxt.implicitWidth + 16
                                            radius: 12
                                            color: disconBtM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.18) : Services.Aesthetic.innerCardBg
                                            border.color: disconBtM.containsMouse ? root.theme.accentRed : Services.Aesthetic.innerCardBorder
                                            border.width: 1
                                            scale: disconBtM.pressed ? 0.94 : (disconBtM.containsMouse ? 1.04 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            Text {
                                                id: disconBtTxt
                                                anchors.centerIn: parent
                                                text: "Disconnect"
                                                color: disconBtM.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: disconBtM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.disconnectBluetooth(modelData.mac)
                                            }
                                        }
                                    }
                                }
                            }

                            // ── PAIRED DEVICES SECTION ────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: btDetailsView.pairedBtDevices.length > 0

                                Text {
                                    text: "PAIRED DEVICES"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 2
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: pairedCol.implicitHeight
                                    radius: 12
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    clip: true

                                    ColumnLayout {
                                        id: pairedCol
                                        width: parent.width
                                        spacing: 0

                                        Repeater {
                                            model: btDetailsView.pairedBtDevices
                                            delegate: ColumnLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 0

                                                // Hairline divider
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Services.Aesthetic.innerCardBorder
                                                    visible: index > 0
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 48
                                                    color: pairedRowM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    MouseArea {
                                                        id: pairedRowM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Services.SystemService.connectBluetooth(modelData.mac)
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 10

                                                        // Neutral circle icon
                                                        Rectangle {
                                                            width: 28
                                                            height: 28
                                                            radius: 14
                                                            color: Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.08)

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: root.getBtIcon(modelData.icon)
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 13
                                                                font.family: root.font
                                                            }
                                                        }

                                                        // Name & details
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1

                                                            Text {
                                                                text: modelData.name || modelData.mac
                                                                color: root.theme.textPrimary
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }

                                                            Text {
                                                                text: "Paired" + (modelData.battery !== null && modelData.battery !== undefined ? (" · " + modelData.battery + "%") : "")
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                            }
                                                        }

                                                        // Forget / Remove icon button (visible on hover)
                                                        Rectangle {
                                                            width: 24
                                                            height: 24
                                                            radius: 6
                                                            visible: pairedRowM.containsMouse || fgtPairedM.containsMouse
                                                            color: fgtPairedM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.15) : "transparent"
                                                            Behavior on color { ColorAnimation { duration: 100 } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰆴"
                                                                color: fgtPairedM.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                                font.pixelSize: 12
                                                                font.family: root.font
                                                            }

                                                            MouseArea {
                                                                id: fgtPairedM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Services.SystemService.removeBluetooth(modelData.mac)
                                                            }
                                                        }

                                                        // Tonal accent Connect pill
                                                        Rectangle {
                                                            id: connPairedBtn
                                                            height: 24
                                                            implicitWidth: connPairedTxt.implicitWidth + 16
                                                            radius: 12
                                                            color: connPairedM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                                                            border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                                            border.width: 1
                                                            scale: connPairedM.pressed ? 0.94 : (connPairedM.containsMouse ? 1.04 : 1.0)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                                            Text {
                                                                id: connPairedTxt
                                                                anchors.centerIn: parent
                                                                text: "Connect"
                                                                color: root.theme.accent
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                                font.weight: Font.Medium
                                                            }

                                                            MouseArea {
                                                                id: connPairedM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Services.SystemService.connectBluetooth(modelData.mac)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty Paired state (single muted line if no devices paired at all)
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                visible: (Services.SystemService.bluetoothDevices || []).length === 0
                                text: "No paired devices"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            // ── NEARBY DEVICES SECTION ────────────
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4

                                Text {
                                    text: "NEARBY DEVICES"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 2
                                }

                                Item { Layout.fillWidth: true }

                                // Searching indicator
                                Row {
                                    spacing: 4
                                    visible: Services.SystemService.bluetoothDiscovering

                                    Text {
                                        text: "󰑐"
                                        color: root.theme.accent
                                        font.pixelSize: 11
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                        transformOrigin: Item.Center
                                        NumberAnimation on rotation {
                                            running: Services.SystemService.bluetoothDiscovering
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 360
                                            duration: 900
                                        }
                                    }

                                    Text {
                                        text: "Searching…"
                                        color: root.theme.accent
                                        font.pixelSize: 10
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            // Empty Available state (single muted line)
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                visible: (Services.SystemService.bluetoothAvailableDevices || []).length === 0
                                text: Services.SystemService.bluetoothDiscovering ? "Searching for nearby devices…" : "No nearby devices found"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            // Discovered Available Devices List
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: nearbyCol.implicitHeight
                                radius: 12
                                visible: (Services.SystemService.bluetoothAvailableDevices || []).length > 0
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                clip: true

                                ColumnLayout {
                                    id: nearbyCol
                                    width: parent.width
                                    spacing: 0

                                    Repeater {
                                        model: Services.SystemService.bluetoothAvailableDevices
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            spacing: 0

                                            // Hairline divider
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: Services.Aesthetic.innerCardBorder
                                                visible: index > 0
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 48
                                                color: nearbyRowM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                MouseArea {
                                                    id: nearbyRowM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Services.SystemService.pairBluetooth(modelData.mac)
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 10

                                                    // Neutral circle icon
                                                    Rectangle {
                                                        width: 28
                                                        height: 28
                                                        radius: 14
                                                        color: Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.08)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.getBtIcon(modelData.icon)
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 13
                                                            font.family: root.font
                                                        }
                                                    }

                                                    // Name & MAC
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        Text {
                                                            text: modelData.name || modelData.mac
                                                            color: root.theme.textPrimary
                                                            font.pixelSize: 12
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }

                                                        Text {
                                                            text: modelData.mac
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 9
                                                            font.family: root.font
                                                        }
                                                    }

                                                    // Tonal accent Pair pill
                                                    Rectangle {
                                                        id: pairBtn
                                                        height: 24
                                                        implicitWidth: pairTxt.implicitWidth + 16
                                                        radius: 12
                                                        color: pairBtnM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                                                        border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                                        border.width: 1
                                                        scale: pairBtnM.pressed ? 0.94 : (pairBtnM.containsMouse ? 1.04 : 1.0)
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Behavior on scale { NumberAnimation { duration: 120 } }

                                                        Text {
                                                            id: pairTxt
                                                            anchors.centerIn: parent
                                                            text: "Pair"
                                                            color: root.theme.accent
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                        }

                                                        MouseArea {
                                                            id: pairBtnM
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: Services.SystemService.pairBluetooth(modelData.mac)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── FOOTER: ADAPTER DISCOVERABILITY ─────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 12
                        visible: Services.SystemService.bluetoothEnabled
                        color: footerCardM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                        border.color: footerCardM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35) : Services.Aesthetic.innerCardBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: footerCardM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemService.toggleBluetoothDiscoverable()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: Services.SystemService.bluetoothDiscoverable ? "󰂰" : "󰂲"
                                color: Services.SystemService.bluetoothDiscoverable ? root.theme.accent : root.theme.textMuted
                                font.pixelSize: 14
                                font.family: root.font
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Now discoverable as \"" + Services.SystemService.bluetoothAdapterName + "\""
                                color: footerCardM.containsMouse ? root.theme.textPrimary : root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Rectangle {
                                height: 24
                                implicitWidth: footerDiscTxt.implicitWidth + 16
                                radius: 12
                                color: Services.SystemService.bluetoothDiscoverable ? (footerCardM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)) : (footerCardM.containsMouse ? Services.Aesthetic.innerCardHover : "transparent")
                                border.color: Services.SystemService.bluetoothDiscoverable ? root.theme.accent : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                scale: footerCardM.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                Text {
                                    id: footerDiscTxt
                                    anchors.centerIn: parent
                                    text: Services.SystemService.bluetoothDiscoverable ? "Visible" : "Hidden"
                                    color: Services.SystemService.bluetoothDiscoverable ? root.theme.accent : root.theme.textMuted
                                    font.pixelSize: 9
                                    font.family: root.font
                                    font.weight: Font.Medium
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW: macOS STYLE NATIVE AUDIO & SOUND DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: audioDetailsView
                    visible: root.activeView === "audio"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    readonly property var activeSink: {
                        const sinks = Services.SystemService.audioSinks || [];
                        for (let i = 0; i < sinks.length; i++) {
                            if (sinks[i].active) return sinks[i];
                        }
                        return sinks.length > 0 ? sinks[0] : null;
                    }
                    readonly property int sinkCount: (Services.SystemService.audioSinks || []).length
                    readonly property bool canToggleSinks: sinkCount > 1

                    readonly property var sortedSinks: {
                        const raw = Services.SystemService.audioSinks || [];
                        const list = raw.slice();
                        list.sort((a, b) => {
                            const nameA = (a && a.name) ? a.name : "";
                            const nameB = (b && b.name) ? b.name : "";
                            const isHdmiA = /hdmi|displayport/i.test(nameA);
                            const isHdmiB = /hdmi|displayport/i.test(nameB);
                            if (isHdmiA !== isHdmiB) return isHdmiA ? 1 : -1;
                            return nameA.localeCompare(nameB, undefined, { sensitivity: "base" });
                        });
                        return list;
                    }

                    readonly property var activeSource: {
                        const srcs = Services.SystemService.audioSources || [];
                        for (let i = 0; i < srcs.length; i++) {
                            if (srcs[i].active) return srcs[i];
                        }
                        return srcs.length > 0 ? srcs[0] : null;
                    }
                    readonly property int sourceCount: (Services.SystemService.audioSources || []).length
                    readonly property bool canToggleSources: sourceCount > 1

                    readonly property var sortedSources: {
                        const raw = Services.SystemService.audioSources || [];
                        const list = raw.slice();
                        list.sort((a, b) => {
                            const nameA = (a && a.name) ? a.name : "";
                            const nameB = (b && b.name) ? b.name : "";
                            const isHdmiA = /hdmi|displayport/i.test(nameA);
                            const isHdmiB = /hdmi|displayport/i.test(nameB);
                            if (isHdmiA !== isHdmiB) return isHdmiA ? 1 : -1;
                            return nameA.localeCompare(nameB, undefined, { sensitivity: "base" });
                        });
                        return list;
                    }

                    function getSinkIcon(sinkName) {
                        if (!sinkName) return "󰓃";
                        const nm = sinkName.toLowerCase();
                        if (nm.includes("hdmi")) return "󰡁";
                        if (nm.includes("headphone") || nm.includes("headset") || nm.includes("airpod") || nm.includes("buds") || nm.includes("earphone") || nm.includes("bluez")) return "󰋋";
                        return "󰓃";
                    }

                    function formatSinkName(rawName) {
                        if (!rawName) return "";
                        let s = ("" + rawName).trim();
                        s = s.replace("Alder Lake PCH-P High Definition Audio Controller ", "");
                        if (s.endsWith(" (Stereo)")) {
                            s = s.slice(0, -9).trim();
                        }
                        return s;
                    }

                    function getMicIcon(sourceName) {
                        if (!sourceName) return "󰍬";
                        const nm = sourceName.toLowerCase();
                        if (nm.includes("headset") || nm.includes("headphone") || nm.includes("airpod") || nm.includes("buds") || nm.includes("earphone") || nm.includes("bluez")) return "󰋎";
                        return "󰍬";
                    }

                    function formatSourceName(rawName) {
                        if (!rawName) return "";
                        let s = ("" + rawName).trim();
                        s = s.replace("Alder Lake PCH-P High Definition Audio Controller ", "");
                        if (s.endsWith(" (Stereo)")) {
                            s = s.slice(0, -9).trim();
                        }
                        return s;
                    }

                    function toggleOutputs() {
                        if (!canToggleSinks) return;
                        const opening = !root.soundOutputsOpen;
                        if (opening) {
                            root.soundInputsOpen = false;
                            Services.SystemService.rescanAudioSinks();
                        }
                        root.soundOutputsOpen = opening;
                    }

                    function toggleInputs() {
                        if (!canToggleSources) return;
                        const opening = !root.soundInputsOpen;
                        if (opening) {
                            root.soundOutputsOpen = false;
                            Services.SystemService.rescanAudioSources();
                        }
                        root.soundInputsOpen = opening;
                    }

                    onVisibleChanged: {
                        if (!visible) {
                            root.soundOutputsOpen = false;
                            root.soundInputsOpen = false;
                        }
                    }
                    Component.onCompleted: {
                        root.soundOutputsOpen = false;
                        root.soundInputsOpen = false;
                    }

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: backAudioM.pressed ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.18) : (backAudioM.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.12) : Services.Aesthetic.innerCardBg)
                            border.color: backAudioM.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.25) : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: backAudioM.pressed ? 0.92 : (backAudioM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backAudioM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Sound"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Rescan button
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: rescAudioM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (rescAudioM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Services.Aesthetic.innerCardBg)
                            border.color: rescAudioM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Services.Aesthetic.innerCardBorder
                            border.width: 1
                            scale: rescAudioM.pressed ? 0.90 : (rescAudioM.containsMouse ? 1.08 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }

                            ToolTip.visible: rescAudioM.containsMouse
                            ToolTip.text: "Rescan Audio Devices"
                            ToolTip.delay: 400

                            MouseArea {
                                id: rescAudioM
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.rescanAudioSinks();
                                    Services.SystemService.rescanAudioSources();
                                    Services.SystemService.rescanAppAudioStreams();
                                }
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: audioDetailCol.implicitHeight + 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: audioDetailCol
                            width: parent.width
                            spacing: 12

                            // ── OUTPUT CARD ──
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                implicitHeight: outputCol.implicitHeight + 24
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    id: outputCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Output"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.SystemService.volumeMuted ? "Muted" : Services.SystemService.volume + "%"
                                            color: Services.SystemService.volumeMuted
                                                ? root.theme.accentRed
                                                : (Services.SystemService.volume > 100 ? root.theme.accentOrange : root.theme.textMuted)
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: (Services.SystemService.volumeMuted || Services.SystemService.volume > 100) ? Font.DemiBold : Font.Normal

                                            ToolTip.visible: volLabelMouse.containsMouse && Services.SystemService.volume > 100
                                            ToolTip.text: "Above 100% may distort"
                                            ToolTip.delay: 300

                                            MouseArea {
                                                id: volLabelMouse
                                                anchors.fill: parent
                                                hoverEnabled: Services.SystemService.volume > 100
                                            }
                                        }
                                    }

                                    // Sound Slider Capsule
                                    Rectangle {
                                        id: subSoundBar
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 16
                                        color: Services.SystemService.volumeMuted ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.25) : Services.Aesthetic.sliderTrackBg
                                        border.color: Services.SystemService.volumeMuted ? root.theme.accentRed : (subSoundMouse.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.18) : Services.Aesthetic.innerCardBorder)
                                        border.width: 1
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.volumeIcon
                                            color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.textMuted
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }

                                        Rectangle {
                                            id: subSoundFill
                                            width: (Services.SystemService.volumeMuted || Services.SystemService.volume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Math.min(100, Services.SystemService.volume) / 100)))
                                            height: parent.height
                                            radius: 16
                                            color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.accent
                                            clip: true
                                            Behavior on width {
                                                enabled: !subSoundMouse.pressed
                                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                            }

                                            Text {
                                                x: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Services.SystemService.volumeIcon
                                                color: root.theme.onPrimary
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        MouseArea {
                                            id: subSoundMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            property real startX: 0
                                            property real startY: 0
                                            property bool isDragging: false
                                            property bool startedInIcon: false

                                            function applyVolume(mouseX) {
                                                const rawPct = (mouseX / subSoundBar.width) * 100;
                                                const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                                Services.SystemService.setVolumePercent(pct);
                                            }

                                            onPressed: (mouse) => {
                                                startX = mouse.x;
                                                startY = mouse.y;
                                                isDragging = false;
                                                startedInIcon = (mouse.x <= 36);
                                                if (!startedInIcon) {
                                                    isDragging = true;
                                                    Services.SystemService.isVolumeDragging = true;
                                                    applyVolume(mouse.x);
                                                }
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    const dx = Math.abs(mouse.x - startX);
                                                    if (!isDragging && (dx > 4 || mouse.x > 36)) {
                                                        isDragging = true;
                                                        startedInIcon = false;
                                                        Services.SystemService.isVolumeDragging = true;
                                                    }
                                                    if (isDragging) {
                                                        applyVolume(mouse.x);
                                                    }
                                                }
                                            }

                                            onReleased: (mouse) => {
                                                if (isDragging) {
                                                    applyVolume(mouse.x);
                                                    Services.SystemService.flushVolume();
                                                    Services.SystemService.isVolumeDragging = false;
                                                    isDragging = false;
                                                } else if (startedInIcon && Math.abs(mouse.x - startX) <= 4) {
                                                    Services.SystemService.toggleMute();
                                                }
                                                startedInIcon = false;
                                            }

                                            onCanceled: {
                                                isDragging = false;
                                                startedInIcon = false;
                                                Services.SystemService.flushVolume();
                                                Services.SystemService.isVolumeDragging = false;
                                            }

                                            onWheel: (wheel) => {
                                                wheel.accepted = true;
                                                const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                                Services.SystemService.adjustVolume(delta);
                                            }
                                        }
                                    }

                                    // Compact Device Row (Default View)
                                    Rectangle {
                                        id: compactDeviceRow
                                        Layout.fillWidth: true
                                        height: 36
                                        radius: 10
                                        color: compactRowMouse.pressed ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.12) : ((compactRowMouse.containsMouse || compactDeviceRow.activeFocus) ? Services.Aesthetic.innerCardHover : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        focus: audioDetailsView.canToggleSinks
                                        activeFocusOnTab: audioDetailsView.canToggleSinks
                                        Keys.onReturnPressed: if (audioDetailsView.canToggleSinks) audioDetailsView.toggleOutputs()
                                        Keys.onSpacePressed: if (audioDetailsView.canToggleSinks) audioDetailsView.toggleOutputs()

                                        MouseArea {
                                            id: compactRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: audioDetailsView.canToggleSinks
                                            cursorShape: audioDetailsView.canToggleSinks ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (audioDetailsView.canToggleSinks) {
                                                    audioDetailsView.toggleOutputs();
                                                }
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Text {
                                                text: audioDetailsView.getSinkIcon(audioDetailsView.activeSink ? audioDetailsView.activeSink.name : "")
                                                color: root.theme.accent
                                                font.pixelSize: 14
                                                font.family: root.font
                                            }

                                            Text {
                                                text: audioDetailsView.formatSinkName(audioDetailsView.activeSink ? audioDetailsView.activeSink.name : "Default Output")
                                                color: root.theme.textPrimary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                font.weight: Font.Medium
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: "⌄"
                                                color: root.soundOutputsOpen ? root.theme.accent : root.theme.textMuted
                                                font.pixelSize: 13
                                                font.family: root.font
                                                font.weight: Font.Medium
                                                visible: audioDetailsView.canToggleSinks
                                                rotation: root.soundOutputsOpen ? 180 : 0
                                                transformOrigin: Item.Center
                                                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }

                                        ToolTip.visible: compactRowMouse.containsMouse && Boolean(audioDetailsView.activeSink) && Boolean(audioDetailsView.activeSink.name)
                                        ToolTip.text: audioDetailsView.activeSink ? audioDetailsView.activeSink.name : ""
                                        ToolTip.delay: 400
                                    }

                                    // Hairline divider before expanded list
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Services.Aesthetic.innerCardBorder
                                        visible: root.soundOutputsOpen || sinksExpandItem.Layout.preferredHeight > 0
                                        opacity: root.soundOutputsOpen ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    // Expandable Animated Device List
                                    Item {
                                        id: sinksExpandItem
                                        Layout.fillWidth: true
                                        clip: true
                                        Layout.preferredHeight: root.soundOutputsOpen ? Math.min(170, sinksInnerCol.implicitHeight) : 0
                                        implicitHeight: Layout.preferredHeight
                                        visible: root.soundOutputsOpen || Layout.preferredHeight > 0
                                        opacity: root.soundOutputsOpen ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Flickable {
                                            anchors.fill: parent
                                            contentWidth: width
                                            contentHeight: sinksInnerCol.implicitHeight
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds

                                            ColumnLayout {
                                                id: sinksInnerCol
                                                width: parent.width
                                                spacing: 0

                                                Repeater {
                                                    model: audioDetailsView.sortedSinks
                                                    delegate: ColumnLayout {
                                                        required property var modelData
                                                        required property int index
                                                        Layout.fillWidth: true
                                                        spacing: 0

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 1
                                                            color: Services.Aesthetic.innerCardBorder
                                                            visible: index > 0
                                                        }

                                                        Rectangle {
                                                            id: sinkRowItem
                                                            Layout.fillWidth: true
                                                            height: 34
                                                            radius: 8
                                                            focus: true
                                                            activeFocusOnTab: true
                                                            Keys.onReturnPressed: {
                                                                if (!modelData.active) {
                                                                    Services.SystemService.setAudioSink(modelData.id);
                                                                }
                                                                root.soundOutputsOpen = false;
                                                            }
                                                            Keys.onSpacePressed: {
                                                                if (!modelData.active) {
                                                                    Services.SystemService.setAudioSink(modelData.id);
                                                                }
                                                                root.soundOutputsOpen = false;
                                                            }
                                                            color: modelData.active
                                                                ? (sinkRowMouse.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.09))
                                                                : ((sinkRowMouse.containsMouse || sinkRowItem.activeFocus) ? Services.Aesthetic.innerCardHover : "transparent")
                                                            Behavior on color { ColorAnimation { duration: 100 } }

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 8
                                                                anchors.rightMargin: 8
                                                                spacing: 8

                                                                Text {
                                                                    text: audioDetailsView.getSinkIcon(modelData.name)
                                                                    color: modelData.active ? root.theme.accent : root.theme.textMuted
                                                                    font.pixelSize: 13
                                                                    font.family: root.font
                                                                }

                                                                Text {
                                                                    text: audioDetailsView.formatSinkName(modelData.name)
                                                                    color: root.theme.textPrimary
                                                                    font.pixelSize: 11
                                                                    font.family: root.font
                                                                    font.weight: modelData.active ? Font.DemiBold : Font.Normal
                                                                    elide: Text.ElideRight
                                                                    Layout.fillWidth: true
                                                                }

                                                                Text {
                                                                    text: "✓"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 12
                                                                    font.weight: Font.Bold
                                                                    visible: modelData.active
                                                                }
                                                            }

                                                            ToolTip.visible: sinkRowMouse.containsMouse && Boolean(modelData.name)
                                                            ToolTip.text: modelData.name || ""
                                                            ToolTip.delay: 400

                                                            MouseArea {
                                                                id: sinkRowMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (!modelData.active) {
                                                                        Services.SystemService.setAudioSink(modelData.id);
                                                                    }
                                                                    root.soundOutputsOpen = false;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── APPLICATIONS (PER-APP VOLUME MIXER) CARD ──
                            Rectangle {
                                id: appMixerCard
                                Layout.fillWidth: true
                                implicitHeight: appMixerCol.implicitHeight + 24
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    id: appMixerCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Applications"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: Services.SystemService.appAudioStreams.length > 0
                                            text: Services.SystemService.appAudioStreams.length + " active"
                                            color: root.theme.textMuted
                                            font.pixelSize: 10
                                            font.family: root.font
                                        }
                                    }

                                    // Empty State
                                    RowLayout {
                                        visible: Services.SystemService.appAudioStreams.length === 0
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.topMargin: 2
                                        Layout.bottomMargin: 4
                                        spacing: 6

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "󰝚"
                                            color: root.theme.textMuted
                                            font.pixelSize: 12
                                            font.family: root.font
                                        }

                                        Text {
                                            text: "No applications playing audio"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }

                                        Item { Layout.fillWidth: true }
                                    }

                                    // Active Streams List
                                    ColumnLayout {
                                        visible: Services.SystemService.appAudioStreams.length > 0
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Repeater {
                                            model: Services.SystemService.appAudioStreams

                                            ColumnLayout {
                                                id: streamRow
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 6

                                                property int currentVol: modelData ? modelData.volume : 100
                                                property bool currentMuted: modelData ? modelData.muted : false
                                                property bool isLocalDragging: false

                                                onModelDataChanged: {
                                                    if (!isLocalDragging && modelData) {
                                                        currentVol = modelData.volume;
                                                        currentMuted = modelData.muted;
                                                    }
                                                }

                                                // App Info Row
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    // App Icon Badge
                                                    Rectangle {
                                                        width: 24
                                                        height: 24
                                                        radius: 12
                                                        color: {
                                                            const s = (modelData.name + " " + modelData.binary).toLowerCase();
                                                            if (s.includes("spotify")) return Qt.rgba(0.11, 0.73, 0.33, 0.2);
                                                            if (s.includes("discord") || s.includes("vesktop")) return Qt.rgba(0.35, 0.40, 0.95, 0.2);
                                                            if (s.includes("firefox")) return Qt.rgba(1, 0.44, 0.22, 0.2);
                                                            if (s.includes("chrome") || s.includes("chromium") || s.includes("brave")) return Qt.rgba(0.26, 0.52, 0.96, 0.2);
                                                            if (s.includes("elisa")) return Qt.rgba(0.16, 0.50, 0.73, 0.2);
                                                            return Qt.rgba(1, 1, 1, 0.08);
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: {
                                                                const s = (modelData.name + " " + modelData.binary).toLowerCase();
                                                                if (s.includes("spotify")) return "";
                                                                if (s.includes("firefox")) return "";
                                                                if (s.includes("chrome") || s.includes("chromium") || s.includes("brave")) return "";
                                                                if (s.includes("discord") || s.includes("vesktop")) return "󰙯";
                                                                if (s.includes("steam")) return "";
                                                                if (s.includes("vlc") || s.includes("mpv")) return "󰕼";
                                                                if (s.includes("elisa") || s.includes("music")) return "󰎆";
                                                                if (s.includes("telegram")) return "󰎦";
                                                                if (s.includes("kitty") || s.includes("terminal")) return "󰆍";
                                                                return "󰝚";
                                                            }
                                                            color: {
                                                                const s = (modelData.name + " " + modelData.binary).toLowerCase();
                                                                if (s.includes("spotify")) return "#1db954";
                                                                if (s.includes("discord") || s.includes("vesktop")) return "#5865f2";
                                                                if (s.includes("firefox")) return "#ff7139";
                                                                if (s.includes("chrome") || s.includes("chromium") || s.includes("brave")) return "#4285f4";
                                                                if (s.includes("elisa")) return "#2980b9";
                                                                return root.theme.textPrimary;
                                                            }
                                                            font.pixelSize: 12
                                                            font.family: root.font
                                                        }
                                                    }

                                                    // App Name & Subtitle
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        Text {
                                                            text: {
                                                                const n = modelData.name || "App";
                                                                if (n === "pw-play") return "Audio Player";
                                                                return n;
                                                            }
                                                            color: root.theme.textPrimary
                                                            font.pixelSize: 12
                                                            font.family: root.font
                                                            font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }

                                                        Text {
                                                            text: modelData.media_name || (streamRow.currentMuted ? "Muted" : "Active playback")
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                            visible: text.length > 0
                                                        }
                                                    }

                                                    // Volume percentage label
                                                    Text {
                                                        text: streamRow.currentMuted ? "Muted" : (streamRow.currentVol + "%")
                                                        color: streamRow.currentMuted ? root.theme.accentRed : root.theme.textMuted
                                                        font.pixelSize: 11
                                                        font.family: root.font
                                                        font.weight: streamRow.currentMuted ? Font.DemiBold : Font.Normal
                                                    }
                                                }

                                                // App Volume Slider Capsule
                                                Rectangle {
                                                    id: appVolBar
                                                    Layout.fillWidth: true
                                                    height: 30
                                                    radius: 15
                                                    color: streamRow.currentMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                                    border.color: streamRow.currentMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (appVolMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                                    border.width: 1
                                                    clip: true
                                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                    // Unfilled Track Icon
                                                    Text {
                                                        x: 10
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: streamRow.currentMuted ? "󰖁" : (streamRow.currentVol > 50 ? "󰕾" : (streamRow.currentVol > 0 ? "󰖀" : "󰖁"))
                                                        color: streamRow.currentMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                                        font.pixelSize: 13
                                                        font.family: root.font
                                                    }

                                                    // Filled Slider Track
                                                    Rectangle {
                                                        id: appVolFill
                                                        width: (streamRow.currentMuted || streamRow.currentVol <= 0) ? 0 : Math.max(0, Math.min(appVolBar.width, appVolBar.width * (Math.min(100, streamRow.currentVol) / 100)))
                                                        height: parent.height
                                                        radius: 15
                                                        color: streamRow.currentMuted ? root.theme.accentRed : root.theme.accent
                                                        clip: true
                                                        Behavior on width {
                                                            enabled: !appVolMouse.pressed
                                                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                                        }

                                                        // Filled Track Icon
                                                        Text {
                                                            x: 10
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: streamRow.currentMuted ? "󰖁" : (streamRow.currentVol > 50 ? "󰕾" : (streamRow.currentVol > 0 ? "󰖀" : "󰖁"))
                                                            color: streamRow.currentMuted ? "#ffffff" : root.theme.onPrimary
                                                            font.pixelSize: 13
                                                            font.family: root.font
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: appVolMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        property real startX: 0
                                                        property real startY: 0
                                                        property bool isDragging: false
                                                        property bool startedInIcon: false

                                                        function applyVolume(mouseX) {
                                                            const rawPct = (mouseX / appVolBar.width) * 100;
                                                            const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                                            streamRow.currentVol = pct;
                                                            streamRow.currentMuted = (pct === 0);
                                                            Services.SystemService.setAppStreamVolume(modelData.id, pct);
                                                        }

                                                        onPressed: (mouse) => {
                                                            startX = mouse.x;
                                                            startY = mouse.y;
                                                            isDragging = false;
                                                            startedInIcon = (mouse.x <= 34);
                                                            if (!startedInIcon) {
                                                                isDragging = true;
                                                                streamRow.isLocalDragging = true;
                                                                Services.SystemService.isAppVolumeDragging = true;
                                                                applyVolume(mouse.x);
                                                            }
                                                        }

                                                        onPositionChanged: (mouse) => {
                                                            if (pressed) {
                                                                const dx = Math.abs(mouse.x - startX);
                                                                if (!isDragging && (dx > 4 || mouse.x > 34)) {
                                                                    isDragging = true;
                                                                    startedInIcon = false;
                                                                    streamRow.isLocalDragging = true;
                                                                    Services.SystemService.isAppVolumeDragging = true;
                                                                }
                                                                if (isDragging) {
                                                                    applyVolume(mouse.x);
                                                                }
                                                            }
                                                        }

                                                        onReleased: (mouse) => {
                                                            if (isDragging) {
                                                                applyVolume(mouse.x);
                                                                Services.SystemService.flushAppStreamVolume();
                                                                Services.SystemService.isAppVolumeDragging = false;
                                                                streamRow.isLocalDragging = false;
                                                                isDragging = false;
                                                            } else if (startedInIcon && Math.abs(mouse.x - startX) <= 4) {
                                                                streamRow.currentMuted = !streamRow.currentMuted;
                                                                Services.SystemService.toggleAppStreamMute(modelData.id);
                                                            }
                                                            startedInIcon = false;
                                                            streamRow.isLocalDragging = false;
                                                            Services.SystemService.isAppVolumeDragging = false;
                                                        }

                                                        onCanceled: {
                                                            isDragging = false;
                                                            startedInIcon = false;
                                                            streamRow.isLocalDragging = false;
                                                            Services.SystemService.isAppVolumeDragging = false;
                                                            Services.SystemService.flushAppStreamVolume();
                                                        }

                                                        onWheel: (wheel) => {
                                                            wheel.accepted = true;
                                                            const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                                            const newVol = Math.max(0, Math.min(100, streamRow.currentVol + delta));
                                                            streamRow.currentVol = newVol;
                                                            streamRow.currentMuted = (newVol === 0);
                                                            Services.SystemService.setAppStreamVolume(modelData.id, newVol);
                                                            Services.SystemService.flushAppStreamVolume();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── INPUT (MICROPHONE) CARD ──
                            Rectangle {
                                id: micCard
                                Layout.fillWidth: true
                                implicitHeight: inputCol.implicitHeight + 24
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    id: inputCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // Header: "Input" on left, percentage on right
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Input"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.SystemService.micMuted ? "Muted" : Services.SystemService.micVolume + "%"
                                            color: Services.SystemService.micMuted
                                                ? root.theme.accentRed
                                                : (Services.SystemService.micVolume > 100 ? root.theme.accentOrange : root.theme.textMuted)
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: (Services.SystemService.micMuted || Services.SystemService.micVolume > 100) ? Font.DemiBold : Font.Normal

                                            ToolTip.visible: micVolLabelMouse.containsMouse && Services.SystemService.micVolume > 100
                                            ToolTip.text: "Above 100% may distort"
                                            ToolTip.delay: 300

                                            MouseArea {
                                                id: micVolLabelMouse
                                                anchors.fill: parent
                                                hoverEnabled: Services.SystemService.micVolume > 100
                                            }
                                        }
                                    }

                                    // Input (Mic) Slider Capsule (always visible, same height and style as Output slider)
                                    Rectangle {
                                        id: subMicBar
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 16
                                        color: Services.SystemService.micMuted ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.25) : Services.Aesthetic.sliderTrackBg
                                        border.color: Services.SystemService.micMuted ? root.theme.accentRed : (subMicMouse.containsMouse ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.18) : Services.Aesthetic.innerCardBorder)
                                        border.width: 1
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                                            color: Services.SystemService.micMuted ? root.theme.accentRed : root.theme.textMuted
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }

                                        Rectangle {
                                            id: subMicFill
                                            width: (Services.SystemService.micMuted || Services.SystemService.micVolume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Math.min(100, Services.SystemService.micVolume) / 100)))
                                            height: parent.height
                                            radius: 16
                                            color: Services.SystemService.micMuted ? root.theme.accentRed : (Services.SystemService.micInUse ? root.theme.accentOrange : root.theme.accent)
                                            clip: true
                                            Behavior on width {
                                                enabled: !subMicMouse.pressed
                                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                            }
                                            Behavior on color { ColorAnimation { duration: 140 } }

                                            Text {
                                                x: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                                                color: (Services.SystemService.micMuted || Services.SystemService.micInUse) ? root.theme.textPrimary : root.theme.onPrimary
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        MouseArea {
                                            id: subMicMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            property real startX: 0
                                            property real startY: 0
                                            property bool isDragging: false
                                            property bool startedInIcon: false

                                            function applyMicVolume(mouseX) {
                                                const rawPct = (mouseX / subMicBar.width) * 100;
                                                const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                                Services.SystemService.setMicVolumePercent(pct);
                                            }

                                            onPressed: (mouse) => {
                                                startX = mouse.x;
                                                startY = mouse.y;
                                                isDragging = false;
                                                startedInIcon = (mouse.x <= 36);
                                                if (!startedInIcon) {
                                                    isDragging = true;
                                                    Services.SystemService.isMicDragging = true;
                                                    applyMicVolume(mouse.x);
                                                }
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    const dx = Math.abs(mouse.x - startX);
                                                    if (!isDragging && (dx > 4 || mouse.x > 36)) {
                                                        isDragging = true;
                                                        startedInIcon = false;
                                                        Services.SystemService.isMicDragging = true;
                                                    }
                                                    if (isDragging) {
                                                        applyMicVolume(mouse.x);
                                                    }
                                                }
                                            }

                                            onReleased: (mouse) => {
                                                if (isDragging) {
                                                    applyMicVolume(mouse.x);
                                                    Services.SystemService.flushMicVolume();
                                                    Services.SystemService.isMicDragging = false;
                                                    isDragging = false;
                                                } else if (startedInIcon && Math.abs(mouse.x - startX) <= 4) {
                                                    Services.SystemService.toggleMicMute();
                                                }
                                                startedInIcon = false;
                                            }

                                            onCanceled: {
                                                isDragging = false;
                                                startedInIcon = false;
                                                Services.SystemService.flushMicVolume();
                                                Services.SystemService.isMicDragging = false;
                                            }

                                            onWheel: (wheel) => {
                                                wheel.accepted = true;
                                                const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                                Services.SystemService.adjustMicVolume(delta);
                                            }
                                        }
                                    }

                                    // Compact Device Row (Default View)
                                    Rectangle {
                                        id: compactMicRow
                                        Layout.fillWidth: true
                                        height: 36
                                        radius: 10
                                        color: compactMicMouse.pressed ? Qt.rgba(root.theme.textPrimary.r, root.theme.textPrimary.g, root.theme.textPrimary.b, 0.12) : ((compactMicMouse.containsMouse || compactMicRow.activeFocus) ? Services.Aesthetic.innerCardHover : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        focus: audioDetailsView.canToggleSources
                                        activeFocusOnTab: audioDetailsView.canToggleSources
                                        Keys.onReturnPressed: if (audioDetailsView.canToggleSources) audioDetailsView.toggleInputs()
                                        Keys.onSpacePressed: if (audioDetailsView.canToggleSources) audioDetailsView.toggleInputs()

                                        MouseArea {
                                            id: compactMicMouse
                                            anchors.fill: parent
                                            hoverEnabled: audioDetailsView.canToggleSources
                                            cursorShape: audioDetailsView.canToggleSources ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (audioDetailsView.canToggleSources) {
                                                    audioDetailsView.toggleInputs();
                                                }
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Text {
                                                text: audioDetailsView.getMicIcon(audioDetailsView.activeSource ? audioDetailsView.activeSource.name : "")
                                                color: root.theme.accent
                                                font.pixelSize: 14
                                                font.family: root.font
                                            }

                                            Text {
                                                text: audioDetailsView.formatSourceName(audioDetailsView.activeSource ? audioDetailsView.activeSource.name : "Default Input")
                                                color: root.theme.textPrimary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                font.weight: Font.Medium
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: "⌄"
                                                color: root.soundInputsOpen ? root.theme.accent : root.theme.textMuted
                                                font.pixelSize: 13
                                                font.family: root.font
                                                font.weight: Font.Medium
                                                visible: audioDetailsView.canToggleSources
                                                rotation: root.soundInputsOpen ? 180 : 0
                                                transformOrigin: Item.Center
                                                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }

                                        ToolTip.visible: compactMicMouse.containsMouse && Boolean(audioDetailsView.activeSource) && Boolean(audioDetailsView.activeSource.name)
                                        ToolTip.text: audioDetailsView.activeSource ? audioDetailsView.activeSource.name : ""
                                        ToolTip.delay: 400
                                    }

                                    // Hairline divider before expanded list
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Services.Aesthetic.innerCardBorder
                                        visible: root.soundInputsOpen || sourcesExpandItem.Layout.preferredHeight > 0
                                        opacity: root.soundInputsOpen ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    // Expandable Animated Sources List
                                    Item {
                                        id: sourcesExpandItem
                                        Layout.fillWidth: true
                                        clip: true
                                        Layout.preferredHeight: root.soundInputsOpen ? Math.min(170, sourcesInnerCol.implicitHeight) : 0
                                        implicitHeight: Layout.preferredHeight
                                        visible: root.soundInputsOpen || Layout.preferredHeight > 0
                                        opacity: root.soundInputsOpen ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Flickable {
                                            anchors.fill: parent
                                            contentWidth: width
                                            contentHeight: sourcesInnerCol.implicitHeight
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds

                                            ColumnLayout {
                                                id: sourcesInnerCol
                                                width: parent.width
                                                spacing: 0

                                                Repeater {
                                                    model: audioDetailsView.sortedSources
                                                    delegate: ColumnLayout {
                                                        required property var modelData
                                                        required property int index
                                                        Layout.fillWidth: true
                                                        spacing: 0

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 1
                                                            color: Services.Aesthetic.innerCardBorder
                                                            visible: index > 0
                                                        }

                                                        Rectangle {
                                                            id: sourceRowItem
                                                            Layout.fillWidth: true
                                                            height: 34
                                                            radius: 8
                                                            focus: true
                                                            activeFocusOnTab: true
                                                            Keys.onReturnPressed: {
                                                                if (!modelData.active) {
                                                                    Services.SystemService.setAudioSource(modelData.id);
                                                                }
                                                                root.soundInputsOpen = false;
                                                            }
                                                            Keys.onSpacePressed: {
                                                                if (!modelData.active) {
                                                                    Services.SystemService.setAudioSource(modelData.id);
                                                                }
                                                                root.soundInputsOpen = false;
                                                            }
                                                            color: modelData.active
                                                                ? (sourceRowMouse.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.09))
                                                                : ((sourceRowMouse.containsMouse || sourceRowItem.activeFocus) ? Services.Aesthetic.innerCardHover : "transparent")
                                                            Behavior on color { ColorAnimation { duration: 100 } }

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 8
                                                                anchors.rightMargin: 8
                                                                spacing: 8

                                                                Text {
                                                                    text: audioDetailsView.getMicIcon(modelData.name)
                                                                    color: modelData.active ? root.theme.accent : root.theme.textMuted
                                                                    font.pixelSize: 13
                                                                    font.family: root.font
                                                                }

                                                                Text {
                                                                    text: audioDetailsView.formatSourceName(modelData.name)
                                                                    color: root.theme.textPrimary
                                                                    font.pixelSize: 11
                                                                    font.family: root.font
                                                                    font.weight: modelData.active ? Font.DemiBold : Font.Normal
                                                                    elide: Text.ElideRight
                                                                    Layout.fillWidth: true
                                                                }

                                                                Text {
                                                                    text: "✓"
                                                                    color: root.theme.accent
                                                                    font.pixelSize: 12
                                                                    font.weight: Font.Bold
                                                                    visible: modelData.active
                                                                }
                                                            }

                                                            ToolTip.visible: sourceRowMouse.containsMouse && Boolean(modelData.name)
                                                            ToolTip.text: modelData.name || ""
                                                            ToolTip.delay: 400

                                                            MouseArea {
                                                                id: sourceRowMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (!modelData.active) {
                                                                        Services.SystemService.setAudioSource(modelData.id);
                                                                    }
                                                                    root.soundInputsOpen = false;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Footer: Sound Settings shortcut
                            Rectangle {
                                id: openAudioRect
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                height: 36
                                radius: 10
                                color: (openAudioSM.containsMouse || openAudioRect.activeFocus) ? Services.Aesthetic.innerCardHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                focus: true
                                activeFocusOnTab: true
                                Keys.onReturnPressed: openAudioSM.trigger()
                                Keys.onSpacePressed: openAudioSM.trigger()

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "󰒓"
                                        color: root.theme.textMuted
                                        font.pixelSize: 13
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Sound Settings…"
                                        color: root.theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: openAudioSM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    function trigger() {
                                        Services.SystemService.runCmd("pavucontrol || systemsettings kcm_pulseaudio");
                                        Services.SystemService.controlCenterOpen = false;
                                    }
                                    onClicked: trigger()
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW: macOS STYLE BATTERY & POWER SETTINGS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: battDetailsView
                    visible: root.activeView === "battery"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back button with hover/press animations
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: backBattM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (backBattM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: backBattM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: backBattM.pressed ? 0.92 : (backBattM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: backBattM.containsMouse ? "#ffffff" : root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backBattM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Battery"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Refresh button
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: rescBattM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (rescBattM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: rescBattM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: rescBattM.pressed ? 0.92 : (rescBattM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: rescBattM.containsMouse ? "#ffffff" : root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }
                            MouseArea {
                                id: rescBattM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.refreshBattery()
                            }
                        }
                    }

                    // Content Scroll Area
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: battDetailCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: battDetailCol
                            width: parent.width
                            spacing: 14

                            // ── 1. BATTERY STATUS CARD ──
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: battStatusInnerCol.implicitHeight + 24
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    id: battStatusInnerCol
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12

                                    // Top Row: Big Icon + Percentage & State + Status Badge
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Rectangle {
                                            width: 44
                                            height: 44
                                            radius: 22
                                            color: (Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged)
                                                   ? Qt.rgba(root.theme.battGood.r, root.theme.battGood.g, root.theme.battGood.b, 0.15)
                                                   : (Services.SystemService.batteryLevel > 20
                                                      ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.15)
                                                      : Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.15))

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.SystemService.batteryIcon
                                                color: (Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged)
                                                       ? root.theme.battGood
                                                       : (Services.SystemService.batteryLevel > 20 ? root.theme.accentGreen : root.theme.accentOrange)
                                                font.pixelSize: 22
                                                font.family: root.font
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            RowLayout {
                                                spacing: 6
                                                Text {
                                                    text: Services.SystemService.batteryLevel + "%"
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 20
                                                    font.family: root.font
                                                    font.weight: Font.Bold
                                                }

                                                Text {
                                                    text: "󱐋"
                                                    color: root.theme.battGood
                                                    font.pixelSize: 14
                                                    font.family: root.font
                                                    visible: Services.SystemService.batteryCharging
                                                }
                                            }

                                            Text {
                                                text: Services.SystemService.batteryCharging ? "Charging" : (Services.SystemService.batteryPlugged ? "Power Adapter (Connected)" : "Discharging on Battery")
                                                color: root.theme.textMuted
                                                font.pixelSize: 11
                                                font.family: root.font
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // Status badge pill
                                        Rectangle {
                                            implicitHeight: 24
                                            implicitWidth: statusPillText.implicitWidth + 16
                                            radius: 12
                                            color: Services.SystemService.batteryCharging
                                                   ? Qt.rgba(root.theme.battGood.r, root.theme.battGood.g, root.theme.battGood.b, 0.2)
                                                   : (Services.SystemService.batteryPlugged
                                                      ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2)
                                                      : Qt.rgba(1, 1, 1, 0.1))

                                            Text {
                                                id: statusPillText
                                                anchors.centerIn: parent
                                                text: Services.SystemService.batteryCharging ? "Charging" : (Services.SystemService.batteryPlugged ? "AC Connected" : "Battery")
                                                color: Services.SystemService.batteryCharging
                                                       ? root.theme.battGood
                                                       : (Services.SystemService.batteryPlugged ? root.theme.accent : root.theme.textSecondary)
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    // Battery Level Progress Capsule
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 8
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        clip: true

                                        Rectangle {
                                            height: parent.height
                                            width: Math.max(8, parent.width * Math.min(1.0, Math.max(0.0, Services.SystemService.batteryLevel / 100.0)))
                                            radius: 4
                                            color: (Services.SystemService.batteryCharging || Services.SystemService.batteryPlugged)
                                                   ? root.theme.battGood
                                                   : (Services.SystemService.batteryLevel > 20 ? root.theme.accentGreen : root.theme.accentOrange)
                                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    // 1px Subtle Divider
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                    }

                                    // Power Details Rows
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Power Source"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.SystemService.batteryPlugged ? "Power Adapter" : "Battery"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Battery Condition"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.SystemService.batteryCondition + (Services.SystemService.batteryHealthPct > 0 ? " (" + Services.SystemService.batteryHealthPct + "%)" : "")
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: Services.SystemService.batteryCycles > 0
                                        Text {
                                            text: "Cycle Count"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.SystemService.batteryCycles + " cycles"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }

                            // ── 2. ENERGY MODE SECTION (macOS Tahoe Radio Selector) ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "ENERGY MODE"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                    Layout.leftMargin: 4
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: energyModesCol.implicitHeight + 12
                                    radius: 16
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1

                                    ColumnLayout {
                                        id: energyModesCol
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 2

                                        // Low Power Mode
                                        Rectangle {
                                            id: modeSaverRow
                                            readonly property bool isSelected: Services.SystemService.powerProfile === "power-saver"
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: isSelected
                                                   ? (modeSaverMouse.containsMouse ? Qt.rgba(0, 0.48, 1, 0.22) : Qt.rgba(0, 0.48, 1, 0.16))
                                                   : (modeSaverMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Rectangle {
                                                    width: 30
                                                    height: 30
                                                    radius: 15
                                                    color: modeSaverRow.isSelected
                                                           ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.25)
                                                           : Qt.rgba(1, 1, 1, 0.07)
                                                    Behavior on color { ColorAnimation { duration: 140 } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰌪"
                                                        color: modeSaverRow.isSelected ? root.theme.accentGreen : root.theme.textSecondary
                                                        font.pixelSize: 14
                                                        font.family: root.font
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    Text {
                                                        text: "Low Power Mode"
                                                        color: modeSaverRow.isSelected ? "#ffffff" : root.theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        font.weight: modeSaverRow.isSelected ? Font.DemiBold : Font.Normal
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }

                                                    Text {
                                                        text: "Reduces energy usage to increase battery life"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Text {
                                                    text: "✓"
                                                    color: root.theme.accent
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    font.family: root.font
                                                    opacity: modeSaverRow.isSelected ? 1.0 : 0.0
                                                    scale: modeSaverRow.isSelected ? 1.0 : 0.6
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                }
                                            }

                                            MouseArea {
                                                id: modeSaverMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.setPowerProfile("power-saver")
                                            }
                                        }

                                        // Divider
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                        }

                                        // Automatic (Balanced)
                                        Rectangle {
                                            id: modeBalRow
                                            readonly property bool isSelected: Services.SystemService.powerProfile === "balanced"
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: isSelected
                                                   ? (modeBalMouse.containsMouse ? Qt.rgba(0, 0.48, 1, 0.22) : Qt.rgba(0, 0.48, 1, 0.16))
                                                   : (modeBalMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Rectangle {
                                                    width: 30
                                                    height: 30
                                                    radius: 15
                                                    color: modeBalRow.isSelected
                                                           ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25)
                                                           : Qt.rgba(1, 1, 1, 0.07)
                                                    Behavior on color { ColorAnimation { duration: 140 } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰾅"
                                                        color: modeBalRow.isSelected ? root.theme.accent : root.theme.textSecondary
                                                        font.pixelSize: 14
                                                        font.family: root.font
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    Text {
                                                        text: "Automatic (Balanced)"
                                                        color: modeBalRow.isSelected ? "#ffffff" : root.theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        font.weight: modeBalRow.isSelected ? Font.DemiBold : Font.Normal
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }

                                                    Text {
                                                        text: "Balances system performance and energy consumption"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Text {
                                                    text: "✓"
                                                    color: root.theme.accent
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    font.family: root.font
                                                    opacity: modeBalRow.isSelected ? 1.0 : 0.0
                                                    scale: modeBalRow.isSelected ? 1.0 : 0.6
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                }
                                            }

                                            MouseArea {
                                                id: modeBalMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.setPowerProfile("balanced")
                                            }
                                        }

                                        // Divider
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                        }

                                        // High Power Mode
                                        Rectangle {
                                            id: modePerfRow
                                            readonly property bool isSelected: Services.SystemService.powerProfile === "performance"
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: isSelected
                                                   ? (modePerfMouse.containsMouse ? Qt.rgba(0, 0.48, 1, 0.22) : Qt.rgba(0, 0.48, 1, 0.16))
                                                   : (modePerfMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Rectangle {
                                                    width: 30
                                                    height: 30
                                                    radius: 15
                                                    color: modePerfRow.isSelected
                                                           ? Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.25)
                                                           : Qt.rgba(1, 1, 1, 0.07)
                                                    Behavior on color { ColorAnimation { duration: 140 } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰓅"
                                                        color: modePerfRow.isSelected ? root.theme.accentOrange : root.theme.textSecondary
                                                        font.pixelSize: 14
                                                        font.family: root.font
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    Text {
                                                        text: "High Power Mode"
                                                        color: modePerfRow.isSelected ? "#ffffff" : root.theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        font.weight: modePerfRow.isSelected ? Font.DemiBold : Font.Normal
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                    }

                                                    Text {
                                                        text: "Optimizes performance for intensive system workloads"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Text {
                                                    text: "✓"
                                                    color: root.theme.accent
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    font.family: root.font
                                                    opacity: modePerfRow.isSelected ? 1.0 : 0.0
                                                    scale: modePerfRow.isSelected ? 1.0 : 0.6
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                }
                                            }

                                            MouseArea {
                                                id: modePerfMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.setPowerProfile("performance")
                                            }
                                        }
                                    }
                                }
                            }

                            // ── 3. SIGNIFICANT ENERGY CONSUMERS / ACTIVITY MONITOR ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "SYSTEM USAGE"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                    Layout.leftMargin: 4
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    radius: 14
                                    color: btopTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: Qt.rgba(0.75, 0.35, 0.95, 0.2)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰻠"
                                                color: "#bf5af2"
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: "Activity Monitor"
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: "CPU " + Services.SystemService.cpuUsage + "  •  RAM " + Services.SystemService.memUsage
                                                color: root.theme.textMuted
                                                font.pixelSize: 9
                                                font.family: root.font
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: "›"
                                            color: root.theme.textMuted
                                            font.pixelSize: 16
                                            font.family: root.font
                                        }
                                    }

                                    MouseArea {
                                        id: btopTileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Services.SystemService.controlCenterOpen = false;
                                            Services.SystemService.openBtop();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 7: macOS STYLE NATIVE DISPLAYS & MONITORS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: displaysDetailsView
                    visible: root.activeView === "displays"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back button with hover/press animations
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: backDispM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (backDispM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: backDispM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: backDispM.pressed ? 0.92 : (backDispM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: backDispM.containsMouse ? "#ffffff" : root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backDispM
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Displays"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Refresh Button
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: refDispM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (refDispM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: refDispM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: refDispM.pressed ? 0.92 : (refDispM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: refDispM.containsMouse ? "#ffffff" : root.theme.textMuted
                                font.pixelSize: 14
                                font.family: root.font
                            }
                            MouseArea {
                                id: refDispM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.rescanMonitors()
                            }
                        }
                    }

                    // Displays Flickable Content
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: dispCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        ColumnLayout {
                            id: dispCol
                            width: parent.width
                            spacing: 12

                            // Multi-Monitor Tabs (visible if > 1 monitor)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: Services.SystemService.monitorsList.length > 1
                                spacing: 8

                                Repeater {
                                    model: Services.SystemService.monitorsList

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: 8
                                        readonly property bool isCur: Services.SystemService.selectedMonitorIndex === index
                                        color: isCur ? root.theme.accent : (monTabM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                        border.color: isCur ? root.theme.accent : "transparent"
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: "󰍹"
                                                color: parent.parent.isCur ? "#ffffff" : root.theme.textMuted
                                                font.pixelSize: 12
                                                font.family: root.font
                                            }
                                            Text {
                                                text: modelData.name || ("Monitor " + (index + 1))
                                                color: parent.parent.isCur ? "#ffffff" : root.theme.textPrimary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                font.weight: parent.parent.isCur ? Font.DemiBold : Font.Normal
                                            }
                                        }

                                        MouseArea {
                                            id: monTabM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Services.SystemService.selectedMonitorIndex = index;
                                                dispModeCard.dropdownOpen = false;
                                            }
                                        }
                                    }
                                }
                            }

                            // 1. Display Information Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 84
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 14

                                    Rectangle {
                                        width: 48
                                        height: 48
                                        radius: 12
                                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                                        border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰍹"
                                            color: root.theme.accent
                                            font.pixelSize: 24
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.description || Services.SystemService.currentMonitor.name) : "Display"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 13
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.width + " × " + Services.SystemService.currentMonitor.height + " · " + Math.round(Services.SystemService.currentMonitor.refreshRate) + " Hz") : "1920 × 1080 · 60 Hz"
                                            color: root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }

                                        RowLayout {
                                            spacing: 6
                                            Rectangle {
                                                width: 6; height: 6; radius: 3
                                                color: "#30d158"
                                            }
                                            Text {
                                                text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.name + (Services.SystemService.currentMonitor.focused ? " · Primary" : "")) : "Connected"
                                                color: "#30d158"
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Display Mode (Combined resolution + refresh-rate dropdown selector)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "DISPLAY MODE"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                    Layout.leftMargin: 4
                                }

                                Rectangle {
                                    id: dispModeCard
                                    property bool dropdownOpen: false
                                    readonly property var uniqueModes: {
                                        const m = Services.SystemService.currentMonitor;
                                        const modes = (m && m.availableModes) ? m.availableModes : [];
                                        const seen = {};
                                        const list = [];
                                        for (let i = 0; i < modes.length; i++) {
                                            const raw = modes[i];
                                            const match = raw.match(/^(\d+)x(\d+)@([\d\.]+)Hz$/);
                                            let key = raw;
                                            let resText = raw;
                                            let hzText = "";
                                            let w = 0, h = 0, hz = 0;
                                            if (match) {
                                                w = parseInt(match[1]);
                                                h = parseInt(match[2]);
                                                hz = Math.round(parseFloat(match[3]));
                                                key = w + "x" + h + "@" + hz;
                                                resText = w + " × " + h;
                                                hzText = hz + " Hz";
                                            }
                                            if (!seen[key]) {
                                                seen[key] = true;
                                                list.push({
                                                    raw: raw,
                                                    key: key,
                                                    width: w,
                                                    height: h,
                                                    refreshRate: hz,
                                                    resText: resText,
                                                    hzText: hzText,
                                                    label: hzText ? (resText + " · " + hzText) : resText
                                                });
                                            }
                                        }
                                        return list;
                                    }

                                    Layout.fillWidth: true
                                    implicitHeight: dropdownOpen ? (modeColLayout.implicitHeight + 16) : 48
                                    radius: 16
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    clip: true
                                    Behavior on implicitHeight {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }

                                    ColumnLayout {
                                        id: modeColLayout
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 0

                                        // Collapsed / Trigger Row: [ 1920 × 1080             60 Hz      ˅ ]
                                        Rectangle {
                                            id: modeHeaderRow
                                            Layout.fillWidth: true
                                            implicitHeight: 32
                                            radius: 10
                                            color: modeHeaderM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 8

                                                Text {
                                                    text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.width + " × " + Services.SystemService.currentMonitor.height) : "1920 × 1080"
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    font.weight: Font.DemiBold
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: Services.SystemService.currentMonitor ? (Math.round(Services.SystemService.currentMonitor.refreshRate) + " Hz") : "60 Hz"
                                                    color: root.theme.textSecondary
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                }

                                                Text {
                                                    text: dispModeCard.dropdownOpen ? "▴" : "▾"
                                                    color: modeHeaderM.containsMouse ? "#ffffff" : root.theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.family: root.font
                                                }
                                            }

                                            MouseArea {
                                                id: modeHeaderM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dispModeCard.dropdownOpen = !dispModeCard.dropdownOpen
                                            }
                                        }

                                        // Divider line
                                        Rectangle {
                                            id: modeDivider
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                            visible: dispModeCard.dropdownOpen && dispModeCard.uniqueModes.length > 0
                                            Layout.topMargin: 4
                                            Layout.bottomMargin: 4
                                        }

                                        // Expanded Dropdown List
                                        ColumnLayout {
                                            id: modeListCol
                                            Layout.fillWidth: true
                                            visible: dispModeCard.dropdownOpen
                                            spacing: 2

                                            Repeater {
                                                model: dispModeCard.uniqueModes

                                                Rectangle {
                                                    id: modeItemRow
                                                    Layout.fillWidth: true
                                                    implicitHeight: 32
                                                    radius: 8
                                                    readonly property bool isCur: {
                                                        const cur = Services.SystemService.currentMonitor;
                                                        if (!cur) return false;
                                                        if (modelData.width > 0 && modelData.height > 0) {
                                                            return cur.width === modelData.width && cur.height === modelData.height && Math.abs(cur.refreshRate - modelData.refreshRate) <= 1.5;
                                                        }
                                                        const curModeStr = cur.width + "x" + cur.height + "@" + cur.refreshRate.toFixed(2) + "Hz";
                                                        return modelData.raw === curModeStr;
                                                    }
                                                    color: isCur ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12) : (modeItemM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 8

                                                        Text {
                                                            text: modelData.label
                                                            color: modeItemRow.isCur ? root.theme.accent : (modeItemM.containsMouse ? root.theme.textPrimary : root.theme.textSecondary)
                                                            font.pixelSize: 11
                                                            font.family: root.font
                                                            font.weight: modeItemRow.isCur ? Font.DemiBold : Font.Normal
                                                            Layout.fillWidth: true
                                                        }

                                                        Text {
                                                            text: "✓"
                                                            color: root.theme.accent
                                                            font.pixelSize: 12
                                                            font.weight: Font.Bold
                                                            font.family: root.font
                                                            visible: modeItemRow.isCur
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: modeItemM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.SystemService.currentMonitor) {
                                                                Services.SystemService.applyMonitorMode(Services.SystemService.currentMonitor.name, modelData.raw);
                                                            }
                                                            dispModeCard.dropdownOpen = false;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. Scaling (Direct selection with presets: 100%, 125%, 150%, 175%, 200% with ✓)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "SCALING"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                    Layout.leftMargin: 4
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: 16
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                { label: "1x", val: 1.0 },
                                                { label: "1.25x", val: 1.25 },
                                                { label: "1.5x", val: 1.50 },
                                                { label: "1.75x", val: 1.75 },
                                                { label: "2x", val: 2.0 }
                                            ]

                                            Rectangle {
                                                id: scalePresetPill
                                                Layout.fillWidth: true
                                                implicitHeight: 48
                                                radius: 8
                                                readonly property bool isSelected: Math.abs(Services.SystemService.monitorScale - modelData.val) < 0.03
                                                color: isSelected ? root.theme.accent : (scalePresetM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                                border.color: isSelected ? root.theme.accent : (scalePresetM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                                                border.width: 1

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 2

                                                    Text {
                                                        text: modelData.label
                                                        color: scalePresetPill.isSelected ? "#ffffff" : (scalePresetM.containsMouse ? root.theme.textPrimary : root.theme.textMuted)
                                                        font.pixelSize: 11
                                                        font.family: root.font
                                                        font.weight: scalePresetPill.isSelected ? Font.DemiBold : Font.Normal
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }

                                                    Text {
                                                        text: scalePresetPill.isSelected ? "✓" : " "
                                                        color: "#ffffff"
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                        font.weight: Font.Bold
                                                        Layout.alignment: Qt.AlignHCenter
                                                        opacity: scalePresetPill.isSelected ? 1.0 : 0.0
                                                    }
                                                }

                                                MouseArea {
                                                    id: scalePresetM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Services.SystemService.setTargetScale(modelData.val)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 4. Orientation (Landscape, Portrait, 180°, 270° with ✓)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "ORIENTATION"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                    Layout.leftMargin: 4
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: 16
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                { label: "Landscape", icon: "󰍹", val: 0 },
                                                { label: "Portrait", icon: "󰍺", val: 1 },
                                                { label: "180°", icon: "󰍹", val: 2 },
                                                { label: "270°", icon: "󰍺", val: 3 }
                                            ]

                                            Rectangle {
                                                id: rotPill
                                                Layout.fillWidth: true
                                                implicitHeight: 48
                                                radius: 8
                                                readonly property bool isCur: Services.SystemService.currentMonitor && Services.SystemService.currentMonitor.transform === modelData.val
                                                color: isCur ? root.theme.accent : (rotPillM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                                border.color: isCur ? root.theme.accent : (rotPillM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                                                border.width: 1

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 2

                                                    Text {
                                                        text: modelData.icon
                                                        color: rotPill.isCur ? "#ffffff" : (rotPillM.containsMouse ? root.theme.textPrimary : root.theme.textMuted)
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }

                                                    Text {
                                                        text: modelData.label
                                                        color: rotPill.isCur ? "#ffffff" : (rotPillM.containsMouse ? root.theme.textPrimary : root.theme.textMuted)
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        font.weight: rotPill.isCur ? Font.DemiBold : Font.Normal
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }

                                                    Text {
                                                        text: rotPill.isCur ? "✓" : " "
                                                        color: "#ffffff"
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        font.weight: Font.Bold
                                                        Layout.alignment: Qt.AlignHCenter
                                                        opacity: rotPill.isCur ? 1.0 : 0.0
                                                    }
                                                }

                                                MouseArea {
                                                    id: rotPillM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.SystemService.currentMonitor) {
                                                            Services.SystemService.setMonitorTransform(Services.SystemService.currentMonitor.name, modelData.val);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                // ═══════════════════════════════════════════
                // VIEW 6: NOW PLAYING / MEDIA DETAILS (1:1 DYNAMIC ISLAND)
                // ═══════════════════════════════════════════
                ColumnLayout {
                    visible: root.activeView === "media"
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Back & Title Header
                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: backMM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: Services.Aesthetic.borderWidth
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backMM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Now Playing"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // 1:1 Dynamic Island Expanded Player Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 190
                        radius: Services.Aesthetic.cardRadius
                        clip: true
                        color: Services.Aesthetic.innerCardBg
                        border.color: Services.Aesthetic.innerCardBorder
                        border.width: Services.Aesthetic.borderWidth

                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            spacing: 10

                            // ╭────┤  ●  Spotify       ˅  ├────╮
                            // Top Header (Anchored Capsule Pill with Left & Right Shoulder Lines)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                // Left shoulder line
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Services.Aesthetic.innerCardBorder
                                }

                                // Centered Header Capsule Pill
                                Rectangle {
                                    id: ccHeaderPill
                                    implicitWidth: ccHeaderPillRow.implicitWidth + 24
                                    implicitHeight: 26
                                    radius: 13
                                    color: ccPillMouse.containsMouse ? Services.Aesthetic.innerCardHover : Qt.rgba(1, 1, 1, Services.Aesthetic.preset === "oled" ? 0.05 : 0.08)
                                    border.color: ccPillMouse.containsMouse ? root.theme.textPrimary : Services.Aesthetic.innerCardBorder
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        id: ccHeaderPillRow
                                        anchors.centerIn: parent
                                        spacing: 8

                                        // Status Dot (Accent)
                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: root.isMediaPlaying ? root.playerAccent : root.theme.textMuted
                                        }

                                        // Source / Player Identity
                                        Text {
                                            text: root.activePlayer?.identity ?? "Spotify"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.family: root.font
                                        }

                                        // Subtle live cava waveform
                                        Row {
                                            spacing: 2
                                            Layout.alignment: Qt.AlignVCenter
                                            height: 11

                                            Repeater {
                                                model: [root.cavaBar0, root.cavaBar1, root.cavaBar2, root.cavaBar3]

                                                Rectangle {
                                                    required property real modelData
                                                    width: 2
                                                    height: Math.max(2, modelData * 9)
                                                    radius: 1
                                                    color: root.isMediaPlaying ? root.playerAccent : root.theme.textMuted
                                                    anchors.bottom: parent.bottom

                                                    Behavior on height {
                                                        NumberAnimation { duration: 60; easing.type: Easing.Linear }
                                                    }
                                                }
                                            }
                                        }

                                        // Chevron / Collapse Icon
                                        Text {
                                            text: "▾"
                                            color: ccPillMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }
                                    }

                                    MouseArea {
                                        id: ccPillMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.SystemService.controlCenterSubView = "main"
                                    }
                                }

                                // Right shoulder line
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Services.Aesthetic.innerCardBorder
                                }
                            }

                            // Middle: Big Album Art + Title & Artist
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14

                                // Album Art (slightly rounded radius 10)
                                Rectangle {
                                    id: ccExpandedArtBox
                                    width: 52
                                    height: 52
                                    radius: 10
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Services.Aesthetic.innerCardBorder
                                    border.width: 1

                                    Image {
                                        id: ccExpandedArt
                                        anchors.fill: parent
                                        source: root.displayTrackArt
                                        fillMode: Image.PreserveAspectCrop
                                        visible: false
                                        asynchronous: true
                                        cache: true
                                    }

                                    Rectangle {
                                        id: ccExpandedArtMask
                                        anchors.fill: parent
                                        radius: 10
                                        color: "#ffffff"
                                        antialiasing: true
                                        visible: false
                                        layer.enabled: true
                                    }

                                    MultiEffect {
                                        id: ccExpandedArtEffect
                                        anchors.fill: parent
                                        source: ccExpandedArt
                                        maskEnabled: true
                                        maskSource: ccExpandedArtMask
                                        visible: ccExpandedArt.status === Image.Ready && root.displayTrackArt !== ""
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: "transparent"
                                        border.color: ccExpandedArtBox.border.color
                                        border.width: ccExpandedArtBox.border.width
                                        antialiasing: true
                                        z: 2
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰝚"
                                        color: root.playerAccent
                                        font.pixelSize: 24
                                        font.family: root.font
                                        visible: !ccExpandedArtEffect.visible
                                    }
                                }

                                // Title & Artist stack
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: root.activePlayer?.trackTitle ?? "Unknown Title"
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.family: root.font
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: root.activePlayer?.trackArtist ?? "Unknown Artist"
                                        color: root.theme.textMuted
                                        font.pixelSize: 12
                                        font.family: root.font
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Bottom: Full-Width Timeline Scrubber (1:14 ━━━━━●━━━━━━ 3:45)
                            RowLayout {
                                id: ccTimelineRow
                                Layout.fillWidth: true
                                spacing: 8

                                property real scrubPos: -1
                                readonly property real livePos: {
                                    const _ = root.clockTick;
                                    return root.activePlayer?.position ?? 0;
                                }
                                readonly property real displayPos: scrubPos >= 0 ? scrubPos : livePos
                                readonly property real totalLen: root.activePlayer?.length ?? 0
                                readonly property real progressRatio: totalLen > 0 ? Math.max(0, Math.min(1.0, displayPos / totalLen)) : 0

                                Text {
                                    text: root.formatTime(ccTimelineRow.displayPos)
                                    color: ccTimelineRow.scrubPos >= 0 ? root.playerAccent : root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: ccTimelineRow.scrubPos >= 0 ? Font.Bold : Font.Normal
                                }

                                Item {
                                    id: ccTrackBarContainer
                                    Layout.fillWidth: true
                                    height: 18

                                    // Track background bar
                                    Rectangle {
                                        id: ccTrackBg
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: ccScrubArea.containsMouse || ccScrubArea.pressed ? 6 : 4
                                        radius: height / 2
                                        color: Services.Aesthetic.sliderTrackBg
                                        Behavior on height { NumberAnimation { duration: 100 } }

                                        // Filled progress bar
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            radius: parent.radius
                                            color: ccScrubArea.pressed ? Qt.darker(root.playerAccent, 1.2) : (ccScrubArea.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : root.playerAccent)
                                            width: parent.width * ccTimelineRow.progressRatio

                                            Behavior on width {
                                                enabled: !ccScrubArea.pressed
                                                NumberAnimation { duration: 200; easing.type: Easing.Linear }
                                            }
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        // Circular scrubber thumb handle
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: Math.max(0, Math.min(parent.width - width, (parent.width * ccTimelineRow.progressRatio) - (width / 2)))
                                            width: ccScrubArea.containsMouse || ccScrubArea.pressed ? 12 : 0
                                            height: width
                                            radius: width / 2
                                            color: "#ffffff"
                                            border.color: root.playerAccent
                                            border.width: 2
                                            visible: width > 0

                                            Behavior on x {
                                                enabled: !ccScrubArea.pressed
                                                NumberAnimation { duration: 200; easing.type: Easing.Linear }
                                            }
                                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    MouseArea {
                                        id: ccScrubArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        function updateFromMouse(mouseX) {
                                            const ratio = Math.max(0, Math.min(1.0, mouseX / width));
                                            ccTimelineRow.scrubPos = ratio * ccTimelineRow.totalLen;
                                        }

                                        onPressed: (mouse) => {
                                            root.isUserScrubbing = true;
                                            updateFromMouse(mouse.x);
                                        }

                                        onPositionChanged: (mouse) => {
                                            if (pressed) {
                                                updateFromMouse(mouse.x);
                                            }
                                        }

                                        onReleased: (mouse) => {
                                            root.isUserScrubbing = false;
                                            if (ccTimelineRow.scrubPos >= 0) {
                                                root.seekTo(ccTimelineRow.scrubPos);
                                                ccTimelineRow.scrubPos = -1;
                                            }
                                        }

                                        onWheel: (wheel) => {
                                            wheel.accepted = true;
                                            const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                            root.seekRelative(delta);
                                        }
                                    }
                                }

                                Text {
                                    text: root.formatTime(ccTimelineRow.totalLen)
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                }
                            }

                            // Centered Playback Controls (⏮  ⏯  ⏭)
                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 24

                                // Previous Track
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: ccPrevMouse.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        color: ccPrevMouse.containsMouse ? root.theme.textPrimary : root.theme.textSecondary
                                        font.pixelSize: 16
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: ccPrevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activePlayer?.previous()
                                    }
                                }

                                // Play / Pause Circle Button
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: ccPlayMouse.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : root.playerAccent
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                        color: "#ffffff"
                                        font.pixelSize: 16
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: ccPlayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activePlayer?.togglePlaying()
                                    }
                                }

                                // Next Track
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: ccNextMouse.containsMouse ? Services.Aesthetic.innerCardHover : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        color: ccNextMouse.containsMouse ? root.theme.textPrimary : root.theme.textSecondary
                                        font.pixelSize: 16
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: ccNextMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activePlayer?.next()
                                    }
                                }
                            }
                        }
                    }

                    // Media Volume Slider Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 82
                        radius: 16
                        color: Services.Aesthetic.innerCardBg
                        border.color: Services.Aesthetic.innerCardBorder
                        border.width: Services.Aesthetic.borderWidth
                        clip: true

                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Volume"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Services.SystemService.volumeMuted ? "Muted" : (Services.SystemService.volume + "%")
                                    color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.textMuted
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            // Interactive Volume Slider Bar
                            Rectangle {
                                id: ccMediaVolBar
                                Layout.fillWidth: true
                                height: 32
                                radius: 16
                                color: Services.SystemService.volumeMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (ccVolMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBorder)
                                border.width: 1
                                clip: true
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                // Background glyph
                                Text {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Services.SystemService.volumeIcon
                                    color: Services.SystemService.volumeMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                    font.pixelSize: 15
                                    font.family: root.font
                                }

                                // Dynamic fill capsule
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: parent.radius
                                    color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.playerAccent
                                    width: (Services.SystemService.volumeMuted || Services.SystemService.volume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))
                                    clip: true

                                    Behavior on width {
                                        enabled: !ccVolMouse.pressed
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }

                                    // Foreground dark glyph
                                    Text {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Services.SystemService.volumeIcon
                                        color: "#ffffff"
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }
                                }

                                MouseArea {
                                    id: ccVolMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    property real startX: 0
                                    property real startY: 0
                                    property bool isDragging: false
                                    property bool startedInIcon: false

                                    function applyVolume(mouseX) {
                                        const rawPct = (mouseX / width) * 100;
                                        const pct = rawPct <= 3 ? 0 : Math.max(0, Math.min(100, Math.round(rawPct)));
                                        Services.SystemService.setVolumePercent(pct);
                                    }

                                    onPressed: (mouse) => {
                                        startX = mouse.x;
                                        startY = mouse.y;
                                        isDragging = false;
                                        startedInIcon = (mouse.x <= 36);
                                        if (!startedInIcon) {
                                            isDragging = true;
                                            Services.SystemService.isVolumeDragging = true;
                                            applyVolume(mouse.x);
                                        }
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (pressed) {
                                            const dx = Math.abs(mouse.x - startX);
                                            if (!isDragging && (dx > 4 || mouse.x > 36)) {
                                                isDragging = true;
                                                startedInIcon = false;
                                                Services.SystemService.isVolumeDragging = true;
                                            }
                                            if (isDragging) {
                                                applyVolume(mouse.x);
                                            }
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        if (isDragging) {
                                            applyVolume(mouse.x);
                                            Services.SystemService.flushVolume();
                                            Services.SystemService.isVolumeDragging = false;
                                            isDragging = false;
                                        } else if (startedInIcon && Math.abs(mouse.x - startX) <= 4) {
                                            Services.SystemService.toggleMute();
                                        }
                                        startedInIcon = false;
                                    }

                                    onCanceled: {
                                        isDragging = false;
                                        startedInIcon = false;
                                        Services.SystemService.flushVolume();
                                        Services.SystemService.isVolumeDragging = false;
                                    }

                                    onWheel: (wheel) => {
                                        wheel.accepted = true;
                                        const delta = wheel.angleDelta.y > 0 ? 5 : -5;
                                        Services.SystemService.adjustVolume(delta);
                                    }
                                }
                            }
                        }
                    }

                    // Media Sources List Header
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Mpris.players.values.length > 0
                        Text {
                            text: "Media Sources"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Mpris.players.values.length + " active"
                            color: root.theme.textMuted
                            font.pixelSize: 10
                            font.family: root.font
                        }
                    }

                    // Sources List
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: Mpris.players.values.length > 0
                        clip: true
                        spacing: 6
                        model: Mpris.players.values

                        delegate: Rectangle {
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: 44
                            radius: 12
                            color: {
                                const isCurrent = root.activePlayer?.identity === modelData.identity;
                                if (srcMouse.containsMouse) return Services.Aesthetic.innerCardHover;
                                return isCurrent ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg;
                            }
                            border.color: root.activePlayer?.identity === modelData.identity ? root.playerAccent : Services.Aesthetic.innerCardBorder
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: "󰝚"
                                    color: root.activePlayer?.identity === modelData.identity ? root.playerAccent : root.theme.textMuted
                                    font.pixelSize: 16
                                    font.family: root.font
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: modelData.identity ?? "Player"
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.family: root.font
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.trackTitle || (modelData.playbackState === MprisPlaybackState.Playing ? "Playing" : "Paused")
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: modelData.playbackState === MprisPlaybackState.Playing ? (modelData.identity?.toLowerCase().includes("spotify") ? "#1db954" : root.theme.accent) : "transparent"
                                    border.color: root.theme.textMuted
                                    border.width: 1
                                }
                            }

                            MouseArea {
                                id: srcMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.preferredPlayerIdentity = modelData.identity;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
