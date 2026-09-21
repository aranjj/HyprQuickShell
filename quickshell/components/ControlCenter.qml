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

    // Sub-view toggle: "main", "wifi", "bluetooth", "audio", "battery", "media", "wallpaper"
    readonly property string activeView: Services.SystemService.controlCenterSubView

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            Services.SystemService.toggleControlCenter();
        }

        function open(): void {
            Services.SystemService.openControlCenter("controls", "main");
        }

        function openSub(sub: string): void {
            Services.SystemService.openControlCenter("controls", sub || "main");
        }

        function close(): void {
            Services.SystemService.controlCenterOpen = false;
        }

        function setProfile(profile: string): void {
            Services.SystemService.setPowerProfile(profile);
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
    property string wifiOtherSsid: ""
    property string wifiOtherPassword: ""

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
            WlrLayershell.keyboardFocus: (root.activeView === "wifi" && (root.wifiPromptSsid !== "" || root.wifiShowOtherNetworkModal)) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
                height: 640
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
                Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Top specular glass highlight
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Services.Aesthetic.cardRadius
                    anchors.rightMargin: Services.Aesthetic.cardRadius
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    z: 10
                }

                // Prevent click dismissal
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                // ── macOS Tahoe Style Segmented Tab Control ──
                Rectangle {
                    id: tabSegmentedBar
                    visible: root.activeView === "main"
                    width: parent.width - 24
                    height: 34
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    // Sliding Pill Indicator
                    Rectangle {
                        id: tabIndicator
                        width: (parent.width - 6) / 2
                        height: 28
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                        x: Services.SystemService.controlCenterTab === "controls" ? 3 : (parent.width / 2)
                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }

                    Row {
                        anchors.fill: parent

                        // Tab 1: Controls
                        Item {
                            width: parent.width / 2
                            height: parent.height

                            Row {
                                anchors.centerIn: parent
                                spacing: 7

                                Item {
                                    width: 14
                                    height: 11
                                    anchors.verticalCenter: parent.verticalCenter

                                    property color iconColor: Services.SystemService.controlCenterTab === "controls" ? "#ffffff" : root.theme.textMuted
                                    Behavior on iconColor { ColorAnimation { duration: 140 } }

                                    // Top Toggle Switch (knob right)
                                    Rectangle {
                                        y: 0
                                        width: 14
                                        height: 4.5
                                        radius: 2.25
                                        color: "transparent"
                                        border.color: parent.iconColor
                                        border.width: 1.1

                                        Rectangle {
                                            x: parent.width - width - 0.8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 2.5
                                            height: 2.5
                                            radius: 1.25
                                            color: parent.border.color
                                        }
                                    }

                                    // Bottom Toggle Switch (knob left)
                                    Rectangle {
                                        y: 6.5
                                        width: 14
                                        height: 4.5
                                        radius: 2.25
                                        color: "transparent"
                                        border.color: parent.iconColor
                                        border.width: 1.1

                                        Rectangle {
                                            x: 0.8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 2.5
                                            height: 2.5
                                            radius: 1.25
                                            color: parent.border.color
                                        }
                                    }
                                }

                                Text {
                                    text: "Controls"
                                    color: Services.SystemService.controlCenterTab === "controls" ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Services.SystemService.controlCenterTab === "controls" ? Font.Bold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Text.NativeRendering
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.controlCenterTab = "controls";
                                    Services.SystemService.controlCenterSubView = "main";
                                }
                            }
                        }

                        // Tab 2: Notifications
                        Item {
                            width: parent.width / 2
                            height: parent.height

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: Services.NotificationService.dnd ? "󰂛" : "󰂚"
                                    color: Services.SystemService.controlCenterTab === "notifications" ? root.theme.accent : root.theme.textMuted
                                    font.pixelSize: 14
                                    font.family: root.font
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    text: "Notifications" + (Services.NotificationService.unreadCount > 0 ? " (" + Services.NotificationService.unreadCount + ")" : "")
                                    color: Services.SystemService.controlCenterTab === "notifications" ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Services.SystemService.controlCenterTab === "notifications" ? Font.Bold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Text.NativeRendering
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.controlCenterTab = "notifications";
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 1: macOS CONTROL CENTER MAIN GRID
                // ═══════════════════════════════════════════
                Flickable {
                    id: mainFlickable
                    visible: Services.SystemService.controlCenterTab === "controls" && root.activeView === "main"
                    anchors.top: tabSegmentedBar.bottom
                    anchors.topMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    contentHeight: mainContentCol.implicitHeight + 20
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: mainContentCol
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        spacing: 8

                        // ═══════════════════════════════════════════
                        // 1. TOP QUADRANT: Connectivity (Left) & Quick Utility Tiles (Right)
                        // ═══════════════════════════════════════════
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Left: Connectivity 2x2 Capsule Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 184
                                implicitHeight: 140
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 4

                                    // Wi-Fi Row
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 38
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
                                                 color: Services.SystemService.wifiEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.12)
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
                                                     font.pixelSize: 10
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
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
                                        implicitHeight: 38
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
                                                 color: Services.SystemService.bluetoothEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.12)
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
                                                     font.pixelSize: 10
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
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
                                        implicitHeight: 38
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
                                                 color: "#30d158"

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
                                                     font.pixelSize: 10
                                                     font.family: root.font
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                 }
                                             }

                                             Text {
                                                 text: "›"
                                                 color: root.theme.textMuted
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
                                implicitHeight: 140
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
                                    anchors.margins: 10
                                    spacing: 0

                                    // Top Header: Thumbnail + Track Info + Cava Waveform + Expand Chevron
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Thumbnail / Art (46x46, slightly rounded radius 8)
                                        Rectangle {
                                            id: ccIosThumbBox
                                            width: 46
                                            height: 46
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
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
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
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
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
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
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
                            spacing: 8

                            // 1. Focus / DND Tile
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 52
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
                                        color: Services.NotificationService.dnd ? root.theme.accentMauve : Qt.rgba(1, 1, 1, 0.12)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.NotificationService.dnd ? "󰂛" : "󰍡"
                                            color: Services.NotificationService.dnd ? "#ffffff" : root.theme.textMuted
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
                                            font.pixelSize: 10
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
                                implicitHeight: 52
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
                                        color: Services.NightLightService.active ? root.theme.accentOrange : Qt.rgba(1, 1, 1, 0.12)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰔎"
                                            color: Services.NightLightService.active ? "#ffffff" : root.theme.textMuted
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
                                            font.pixelSize: 10
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
                                implicitHeight: 52
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
                                        color: Services.SystemService.caffeineActive ? root.theme.accentYellow : (Services.SystemService.idleInhibited ? Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.25) : Qt.rgba(1, 1, 1, 0.12))
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅶"
                                            color: Services.SystemService.caffeineActive ? "#000000" : (Services.SystemService.idleInhibited ? root.theme.accentYellow : root.theme.textMuted)
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
                                            font.pixelSize: 10
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
                            implicitHeight: 82
                            radius: 16
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

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
                                }

                                // Modern macOS Tahoe Capsule Slider Track
                                Rectangle {
                                    id: brightBar
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 16
                                    color: Services.Aesthetic.sliderTrackBg
                                    border.color: brightMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09)
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
                            implicitHeight: 82
                            radius: 16
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

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
                                    border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (soundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
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
                            spacing: 8

                            // 1. Screen Capture Tile (opens floating screenshot module)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: 14
                                color: snapTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
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
                                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2)

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
                                            font.pixelSize: 10
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
                                implicitHeight: 52
                                radius: 14
                                color: powerMenuTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.2)

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
                                            font.pixelSize: 10
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
                            spacing: 8

                            // Battery Card
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: 14
                                color: battTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

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
                                            font.pixelSize: 10
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
                                implicitHeight: 52
                                radius: 14
                                color: dispTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

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
                                            text: Services.SystemService.currentMonitor ? (Services.SystemService.currentMonitor.name + "  •  " + Math.round(Services.SystemService.monitorScale * 100) + "%") : "Displays"
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
                                            font.pixelSize: 10
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
                            color: backWM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (backWM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: backWM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: backWM.pressed ? 0.92 : (backWM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: backWM.containsMouse ? "#ffffff" : root.theme.textPrimary
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
                                    root.wifiPromptSsid = "";
                                    root.wifiShowOtherNetworkModal = false;
                                    Services.SystemService.controlCenterSubView = "main";
                                }
                            }
                        }

                        Text {
                            text: "Wi-Fi"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }

                        Item { Layout.fillWidth: true }

                        // Status pill badge
                        Rectangle {
                            height: 26
                            implicitWidth: wifiPillRow.implicitWidth + 16
                            radius: 13
                            visible: Services.SystemService.wifiEnabled
                            color: Services.SystemService.wifiConnected ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: Services.SystemService.wifiConnected ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.35) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1

                            Row {
                                id: wifiPillRow
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Services.SystemService.wifiConnected ? root.theme.accentGreen : (Services.SystemService.wifiConnecting ? root.theme.accent : root.theme.textMuted)
                                }
                                Text {
                                    text: Services.SystemService.wifiConnecting ? "Connecting" : (Services.SystemService.wifiConnected ? (Services.SystemService.wifiActiveNetwork?.band || "Connected") : "Disconnected")
                                    color: Services.SystemService.wifiConnected ? root.theme.accentGreen : root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Text.NativeRendering
                                }
                            }
                        }

                        // Rescan button with rotation & scale
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            visible: Services.SystemService.wifiEnabled
                            color: rescWM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (rescWM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: rescWM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: rescWM.pressed ? 0.90 : (rescWM.containsMouse ? 1.08 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: Services.SystemService.wifiScanning ? root.theme.accentGreen : (rescWM.containsMouse ? "#ffffff" : root.theme.accent)
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
                            color: Services.SystemService.wifiEnabled ? (pwrWifiSwMouse.containsMouse ? Qt.lighter(root.theme.accentGreen, 1.1) : root.theme.accentGreen) : (pwrWifiSwMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.15))
                            scale: pwrWifiSwMouse.pressed ? 0.94 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
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
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.1)
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
                                text: "Wi-Fi is Turned Off"
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
                                color: turnOnWifiM.pressed ? Qt.darker(root.theme.accentGreen, 1.15) : (turnOnWifiM.containsMouse ? Qt.lighter(root.theme.accentGreen, 1.15) : root.theme.accentGreen)
                                scale: turnOnWifiM.pressed ? 0.94 : (turnOnWifiM.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Turn On"
                                    color: "#ffffff"
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
                        visible: Services.SystemService.wifiEnabled
                        contentWidth: width
                        contentHeight: wifiContentCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiContentCol
                            width: parent.width
                            Layout.fillWidth: true
                            Layout.preferredWidth: parent.width
                            Layout.maximumWidth: parent.width
                            spacing: 12

                            // ── CONNECTED HERO CARD ───────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: wifiContentCol.width
                                Layout.maximumWidth: wifiContentCol.width
                                width: wifiContentCol.width
                                spacing: 6
                                visible: Services.SystemService.wifiConnected && Services.SystemService.wifiActiveNetwork !== null

                                Text {
                                    text: "CONNECTED NETWORK"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 2
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: wifiContentCol.width
                                    Layout.maximumWidth: wifiContentCol.width
                                    width: wifiContentCol.width
                                    implicitHeight: activeNetCol.implicitHeight + 20
                                    radius: 12
                                    clip: true
                                    color: Services.Aesthetic.innerCardBg
                                    border.color: Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.35)
                                    border.width: 1

                                    ColumnLayout {
                                        id: activeNetCol
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        // Top Section: Icon + Network Info + Disconnect Button
                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(actIconRect.height, actNetInfoCol.implicitHeight)

                                            // Network Icon (left)
                                            Rectangle {
                                                id: actIconRect
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                width: 36
                                                height: 36
                                                radius: 10
                                                color: Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.18)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: root.theme.accentGreen
                                                    font.pixelSize: 18
                                                    font.family: root.font
                                                }
                                            }

                                            // Disconnect Pill Button (pinned to right edge - NEVER shifts or clips!)
                                            Rectangle {
                                                id: actDisconBtn
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.topMargin: 2
                                                width: 68
                                                height: 24
                                                radius: 12
                                                color: disconWM.pressed ? Qt.darker("#ff453a", 1.2) : (disconWM.containsMouse ? "#ff453a" : Qt.rgba(1, 0.27, 0.23, 0.15))
                                                border.color: disconWM.containsMouse ? "#ff453a" : Qt.rgba(1, 0.27, 0.23, 0.3)
                                                border.width: 1
                                                scale: disconWM.pressed ? 0.94 : (disconWM.containsMouse ? 1.04 : 1.0)
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                                Behavior on scale { NumberAnimation { duration: 120 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Disconnect"
                                                    color: disconWM.containsMouse ? "#ffffff" : "#ff453a"
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

                                            // Center info column (rigidly bounded between icon and disconnect)
                                            Column {
                                                id: actNetInfoCol
                                                anchors.left: actIconRect.right
                                                anchors.leftMargin: 10
                                                anchors.right: actDisconBtn.left
                                                anchors.rightMargin: 8
                                                spacing: 3

                                                // Row 1: SSID + Badges
                                                RowLayout {
                                                    width: parent.width
                                                    spacing: 6

                                                    Text {
                                                        text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.ssid || Services.SystemService.wifiSsid) : Services.SystemService.wifiSsid
                                                        color: root.theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: root.font
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    // Band badge (5 GHz / 2.4 GHz)
                                                    Rectangle {
                                                        visible: !!(Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.band)
                                                        height: 16
                                                        implicitWidth: actBandTxt.implicitWidth + 8
                                                        radius: 4
                                                        color: Qt.rgba(1, 1, 1, 0.08)

                                                        Text {
                                                            id: actBandTxt
                                                            anchors.centerIn: parent
                                                            text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.band || "") : ""
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 9
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                        }
                                                    }

                                                    // Security badge
                                                    Rectangle {
                                                        visible: !!(Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.security)
                                                        height: 16
                                                        implicitWidth: actSecTxt.implicitWidth + 8
                                                        radius: 4
                                                        color: Qt.rgba(1, 1, 1, 0.08)

                                                        Text {
                                                            id: actSecTxt
                                                            anchors.centerIn: parent
                                                            text: Services.SystemService.wifiActiveNetwork ? (Services.SystemService.wifiActiveNetwork.security || "") : ""
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 9
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                        }
                                                    }
                                                }

                                                // Row 2: Status & Signal subtitle
                                                Row {
                                                    spacing: 5

                                                    Text {
                                                        text: "Connected"
                                                        color: root.theme.accentGreen
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                        font.weight: Font.Medium
                                                    }
                                                    Text {
                                                        text: "•"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 8
                                                        font.family: root.font
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    Text {
                                                        text: Services.SystemService.wifiActiveNetwork ? ((Services.SystemService.wifiActiveNetwork.signal || 50) + "% Signal") : ""
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                    }
                                                }

                                                // Row 3: Live Speeds (rigid fixed width per stream, zero shifting!)
                                                Row {
                                                    spacing: 10

                                                    Row {
                                                        spacing: 3
                                                        Text {
                                                            text: "↓"
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                        }
                                                        Text {
                                                            text: Services.SystemService.wifiRxFormatted
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            font.features: { "tnum": 1 }
                                                            width: 54
                                                        }
                                                    }

                                                    Text {
                                                        text: "•"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 8
                                                        font.family: root.font
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    Row {
                                                        spacing: 3
                                                        Text {
                                                            text: "↑"
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                        }
                                                        Text {
                                                            text: Services.SystemService.wifiTxFormatted
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            font.features: { "tnum": 1 }
                                                            width: 54
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Divider line
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                        }

                                        // Technical metrics row: IP + Disclosure toggle (pinned to edges!)
                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: 20

                                            Text {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "IP: " + (Services.SystemService.wifiActiveNetwork ? Services.SystemService.wifiActiveNetwork.ip : "Connected")
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                            }

                                            // Details toggle button (pinned to right edge!)
                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: 20
                                                width: dtRow.implicitWidth + 12
                                                radius: 6
                                                color: dtMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                Row {
                                                    id: dtRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: root.wifiShowActiveDetails ? "Hide" : "Details"
                                                        color: dtMouse.containsMouse ? "#ffffff" : root.theme.textMuted
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        font.weight: Font.Medium
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    Text {
                                                        text: root.wifiShowActiveDetails ? "▲" : "▼"
                                                        color: dtMouse.containsMouse ? "#ffffff" : root.theme.textMuted
                                                        font.pixelSize: 7
                                                        anchors.verticalCenter: parent.verticalCenter
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
                                        }

                                        // Expandable Details
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            visible: root.wifiShowActiveDetails

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: Qt.rgba(1, 1, 1, 0.04)
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Gateway:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork?.gateway || "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "DNS:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork?.dns || "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font; elide: Text.ElideLeft; Layout.maximumWidth: 180 }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "BSSID (MAC):"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork?.bssid || "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: !!(Services.SystemService.wifiActiveNetwork && Services.SystemService.wifiActiveNetwork.rate)
                                                Text { text: "Link Speed:"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                                Item { Layout.fillWidth: true }
                                                Text { text: Services.SystemService.wifiActiveNetwork?.rate || "--"; color: root.theme.textPrimary; font.pixelSize: 10; font.family: root.font }
                                            }

                                            // Forget this network button
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 28
                                                radius: 6
                                                color: fgtActiveM.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.15) : Qt.rgba(1, 1, 1, 0.04)
                                                border.color: fgtActiveM.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.3) : Qt.rgba(1, 1, 1, 0.06)
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: "󰆴"; color: "#ff453a"; font.pixelSize: 11; font.family: root.font; anchors.verticalCenter: parent.verticalCenter }
                                                    Text { text: "Forget This Network"; color: "#ff453a"; font.pixelSize: 10; font.family: root.font; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
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

                                Repeater {
                                    model: Services.SystemService.wifiKnownNetworks

                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: 10
                                        color: knownItemM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                        border.color: knownItemM.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Services.Aesthetic.innerCardBorder
                                        border.width: 1
                                        scale: knownItemM.pressed ? 0.985 : 1.0
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                        Behavior on scale { NumberAnimation { duration: 100 } }

                                        MouseArea {
                                            id: knownItemM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.SystemService.connectWifi(modelData.ssid)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            // Signal icon
                                            Rectangle {
                                                width: 28
                                                height: 28
                                                radius: 7
                                                color: Qt.rgba(1, 1, 1, 0.08)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.getWifiSignalIcon(modelData.signal)
                                                    color: root.theme.accent
                                                    font.pixelSize: 14
                                                    font.family: root.font
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                RowLayout {
                                                    spacing: 5
                                                    Text {
                                                        text: modelData.ssid
                                                        color: root.theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: 150
                                                    }
                                                    Text {
                                                        text: "★"
                                                        color: root.theme.accentYellow || "#f39c12"
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                RowLayout {
                                                    spacing: 4
                                                    Text {
                                                        text: "󰌾"
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                        visible: modelData.is_locked
                                                    }
                                                    Text {
                                                        text: (modelData.security || "Secured") + " • " + (modelData.band || "2.4 GHz")
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Connect button
                                            Rectangle {
                                                width: isThisConnecting ? 80 : 64
                                                height: 26
                                                radius: 13
                                                readonly property bool isThisConnecting: Services.SystemService.wifiConnecting && Services.SystemService.wifiConnectingSsid === modelData.ssid
                                                color: isThisConnecting ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (connKnownM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)
                                                scale: connKnownM.pressed ? 0.94 : (connKnownM.containsMouse ? 1.04 : 1.0)
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Behavior on scale { NumberAnimation { duration: 120 } }

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: "󰑐"
                                                        color: "#ffffff"
                                                        font.pixelSize: 11
                                                        font.family: root.font
                                                        visible: parent.parent.isThisConnecting
                                                        transformOrigin: Item.Center
                                                        NumberAnimation on rotation {
                                                            running: parent.parent.parent.isThisConnecting
                                                            loops: Animation.Infinite
                                                            from: 0
                                                            to: 360
                                                            duration: 800
                                                        }
                                                    }
                                                    Text {
                                                        text: parent.parent.isThisConnecting ? "Joining" : "Connect"
                                                        color: "#ffffff"
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

                                            // Forget icon button
                                            Rectangle {
                                                width: 26
                                                height: 26
                                                radius: 6
                                                color: fgtKnownM.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.2) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰆴"
                                                    color: fgtKnownM.containsMouse ? "#ff453a" : root.theme.textMuted
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

                                // Empty Placeholder
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: 10
                                    visible: Services.SystemService.wifiOtherNetworks.length === 0
                                    color: Qt.rgba(1, 1, 1, 0.03)
                                    border.color: Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.SystemService.wifiScanning ? "Scanning for networks..." : "No other networks found"
                                        color: root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                    }
                                }

                                Repeater {
                                    model: Services.SystemService.wifiOtherNetworks

                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        readonly property bool isPromptOpen: root.wifiPromptSsid === modelData.ssid
                                        readonly property bool isThisConnecting: Services.SystemService.wifiConnecting && Services.SystemService.wifiConnectingSsid === modelData.ssid
                                        implicitHeight: isPromptOpen ? (cardRow.implicitHeight + passBox.implicitHeight + 24) : 48
                                        radius: 10
                                        color: isPromptOpen ? Qt.rgba(1, 1, 1, 0.07) : (otherRowM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg)
                                        border.color: isPromptOpen ? root.theme.accent : (otherRowM.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Services.Aesthetic.innerCardBorder)
                                        border.width: 1
                                        clip: true
                                        Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                        MouseArea {
                                            id: otherRowM
                                            anchors.fill: parent
                                            visible: !isPromptOpen
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!modelData.is_locked) {
                                                    Services.SystemService.connectWifi(modelData.ssid);
                                                } else {
                                                    root.wifiPromptSsid = modelData.ssid;
                                                    root.wifiPasswordText = "";
                                                    Services.SystemService.wifiConnectError = "";
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            // Main Row
                                            RowLayout {
                                                id: cardRow
                                                Layout.fillWidth: true
                                                spacing: 10

                                                Rectangle {
                                                    width: 28
                                                    height: 28
                                                    radius: 7
                                                    color: Qt.rgba(1, 1, 1, 0.08)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.getWifiSignalIcon(modelData.signal)
                                                        color: root.theme.accent
                                                        font.pixelSize: 14
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
                                                        Layout.maximumWidth: 150
                                                    }

                                                    RowLayout {
                                                        spacing: 4
                                                        Text {
                                                            text: "󰌾"
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 9
                                                            font.family: root.font
                                                            visible: modelData.is_locked
                                                        }
                                                        Text {
                                                            text: (modelData.security || "Open") + " • " + (modelData.band || "2.4 GHz")
                                                            color: root.theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                        }
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Connect or Lock indicator pill
                                                Rectangle {
                                                    width: isThisConnecting ? 80 : 64
                                                    height: 26
                                                    radius: 13
                                                    color: isThisConnecting ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (otherConnM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : Qt.rgba(1, 1, 1, 0.1))
                                                    border.color: isThisConnecting ? root.theme.accent : (otherConnM.containsMouse ? root.theme.accent : Qt.rgba(1, 1, 1, 0.15))
                                                    border.width: 1
                                                    scale: otherConnM.pressed ? 0.94 : (otherConnM.containsMouse ? 1.04 : 1.0)
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                                    Row {
                                                        anchors.centerIn: parent
                                                        spacing: 4
                                                        Text {
                                                            text: "󰑐"
                                                            color: "#ffffff"
                                                            font.pixelSize: 11
                                                            font.family: root.font
                                                            visible: isThisConnecting
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
                                                            text: isThisConnecting ? "Joining" : (modelData.is_locked ? "Connect" : "Join")
                                                            color: "#ffffff"
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: otherConnM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (!modelData.is_locked) {
                                                                Services.SystemService.connectWifi(modelData.ssid);
                                                            } else {
                                                                if (root.wifiPromptSsid === modelData.ssid) {
                                                                    root.wifiPromptSsid = "";
                                                                } else {
                                                                    root.wifiPromptSsid = modelData.ssid;
                                                                    root.wifiPasswordText = "";
                                                                    Services.SystemService.wifiConnectError = "";
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Inline Password Box
                                            ColumnLayout {
                                                id: passBox
                                                Layout.fillWidth: true
                                                spacing: 8
                                                visible: isPromptOpen

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Qt.rgba(1, 1, 1, 0.08)
                                                }

                                                Text {
                                                    text: "Enter Password for \"" + modelData.ssid + "\""
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 11
                                                    font.family: root.font
                                                    font.weight: Font.Medium
                                                }

                                                // Password Input Box
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 32
                                                    radius: 8
                                                    color: Qt.rgba(0, 0, 0, 0.3)
                                                    border.color: passTextInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 6
                                                        spacing: 6

                                                        TextInput {
                                                            id: passTextInput
                                                            Layout.fillWidth: true
                                                            Layout.alignment: Qt.AlignVCenter
                                                            color: "#ffffff"
                                                            font.pixelSize: 12
                                                            font.family: root.font
                                                            echoMode: root.wifiShowPasswordText ? TextInput.Normal : TextInput.Password
                                                            text: root.wifiPasswordText
                                                            onTextChanged: root.wifiPasswordText = text
                                                            Keys.onReturnPressed: {
                                                                if (text.length > 0) {
                                                                    Services.SystemService.connectWifiWithPassword(modelData.ssid, text);
                                                                }
                                                            }

                                                            Text {
                                                                anchors.fill: parent
                                                                text: "Password"
                                                                color: Qt.rgba(1, 1, 1, 0.4)
                                                                font: parent.font
                                                                visible: !parent.text && !parent.activeFocus
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        // Eye toggle
                                                        Rectangle {
                                                            width: 24
                                                            height: 24
                                                            radius: 6
                                                            color: eyeM.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: root.wifiShowPasswordText ? "󰈈" : "󰈉"
                                                                color: root.wifiShowPasswordText ? root.theme.accent : root.theme.textMuted
                                                                font.pixelSize: 14
                                                                font.family: root.font
                                                            }
                                                            MouseArea {
                                                                id: eyeM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.wifiShowPasswordText = !root.wifiShowPasswordText
                                                            }
                                                        }
                                                    }
                                                }

                                                // Error message banner
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: errRow.implicitHeight + 8
                                                    radius: 6
                                                    color: Qt.rgba(1, 0.27, 0.23, 0.15)
                                                    border.color: Qt.rgba(1, 0.27, 0.23, 0.3)
                                                    border.width: 1
                                                    visible: !!Services.SystemService.wifiConnectError

                                                    RowLayout {
                                                        id: errRow
                                                        anchors.fill: parent
                                                        anchors.margins: 6
                                                        spacing: 6

                                                        Text { text: "󰅚"; color: "#ff453a"; font.pixelSize: 12; font.family: root.font }
                                                        Text {
                                                            text: Services.SystemService.wifiConnectError
                                                            color: "#ff453a"
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.Wrap
                                                        }
                                                    }
                                                }

                                                // Buttons: Cancel & Join
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Item { Layout.fillWidth: true }

                                                    Rectangle {
                                                        width: 60
                                                        height: 26
                                                        radius: 13
                                                        color: cancelPassM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                                                        scale: cancelPassM.pressed ? 0.94 : 1.0

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "Cancel"
                                                            color: root.theme.textPrimary
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                        }

                                                        MouseArea {
                                                            id: cancelPassM
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
                                                        width: 68
                                                        height: 26
                                                        radius: 13
                                                        readonly property bool canConnect: root.wifiPasswordText.length > 0 && !Services.SystemService.wifiConnecting
                                                        color: canConnect ? (joinPassM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)
                                                        scale: joinPassM.pressed ? 0.94 : (joinPassM.containsMouse ? 1.04 : 1.0)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        Behavior on scale { NumberAnimation { duration: 100 } }

                                                        Row {
                                                            anchors.centerIn: parent
                                                            spacing: 4
                                                            Text {
                                                                text: "󰑐"
                                                                color: "#ffffff"
                                                                font.pixelSize: 11
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
                                                                text: Services.SystemService.wifiConnecting ? "Joining" : "Join"
                                                                color: parent.parent.canConnect ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                                font.weight: Font.DemiBold
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: joinPassM
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: parent.canConnect ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                            onClicked: {
                                                                if (parent.canConnect) {
                                                                    Services.SystemService.connectWifiWithPassword(modelData.ssid, root.wifiPasswordText);
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

                            // ── JOIN OTHER NETWORK BUTTON ─────────
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: root.wifiShowOtherNetworkModal ? (otherNetBtnRow.implicitHeight + otherNetFormCol.implicitHeight + 20) : 38
                                radius: 10
                                color: root.wifiShowOtherNetworkModal ? Qt.rgba(1, 1, 1, 0.08) : (joinOtherM.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05))
                                border.color: root.wifiShowOtherNetworkModal ? root.theme.accent : (joinOtherM.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08))
                                border.width: 1
                                clip: true
                                Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    RowLayout {
                                        id: otherNetBtnRow
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "󱛄"
                                            color: root.theme.accent
                                            font.pixelSize: 14
                                            font.family: root.font
                                        }

                                        Text {
                                            text: "Join Other Network..."
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: root.wifiShowOtherNetworkModal ? "▲" : "▼"
                                            color: root.theme.textMuted
                                            font.pixelSize: 8
                                        }
                                    }

                                    // Other Network Form
                                    ColumnLayout {
                                        id: otherNetFormCol
                                        Layout.fillWidth: true
                                        spacing: 8
                                        visible: root.wifiShowOtherNetworkModal

                                        // SSID input
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 32
                                            radius: 8
                                            color: Qt.rgba(0, 0, 0, 0.3)
                                            border.color: otherSsidInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 6

                                                TextInput {
                                                    id: otherSsidInput
                                                    Layout.fillWidth: true
                                                    color: "#ffffff"
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    text: root.wifiOtherSsid
                                                    onTextChanged: root.wifiOtherSsid = text

                                                    Text {
                                                        anchors.fill: parent
                                                        text: "Network Name (SSID)"
                                                        color: Qt.rgba(1, 1, 1, 0.4)
                                                        font: parent.font
                                                        visible: !parent.text && !parent.activeFocus
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Password input
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 32
                                            radius: 8
                                            color: Qt.rgba(0, 0, 0, 0.3)
                                            border.color: otherPassInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 6

                                                TextInput {
                                                    id: otherPassInput
                                                    Layout.fillWidth: true
                                                    color: "#ffffff"
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    echoMode: TextInput.Password
                                                    text: root.wifiOtherPassword
                                                    onTextChanged: root.wifiOtherPassword = text

                                                    Text {
                                                        anchors.fill: parent
                                                        text: "Password (optional for open)"
                                                        color: Qt.rgba(1, 1, 1, 0.4)
                                                        font: parent.font
                                                        visible: !parent.text && !parent.activeFocus
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Form buttons
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Item { Layout.fillWidth: true }

                                            Rectangle {
                                                width: 60
                                                height: 26
                                                radius: 13
                                                color: cancelOtherM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Cancel"
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                }

                                                MouseArea {
                                                    id: cancelOtherM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.wifiShowOtherNetworkModal = false;
                                                        root.wifiOtherSsid = "";
                                                        root.wifiOtherPassword = "";
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 68
                                                height: 26
                                                radius: 13
                                                readonly property bool canJoin: root.wifiOtherSsid.trim().length > 0 && !Services.SystemService.wifiConnecting
                                                color: canJoin ? (joinHiddenM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Connect"
                                                    color: parent.canJoin ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                    font.weight: Font.DemiBold
                                                }

                                                MouseArea {
                                                    id: joinHiddenM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: parent.canJoin ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        if (parent.canJoin) {
                                                            Services.SystemService.connectHiddenWifi(root.wifiOtherSsid.trim(), root.wifiOtherPassword);
                                                            root.wifiShowOtherNetworkModal = false;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: joinOtherM
                                    anchors.fill: parent
                                    visible: !root.wifiShowOtherNetworkModal
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.wifiShowOtherNetworkModal = true
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 3: macOS STYLE BLUETOOTH DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    id: btDetailsView
                    visible: root.activeView === "bluetooth"
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
                            color: backBM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (backBM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: backBM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: backBM.pressed ? 0.92 : (backBM.containsMouse ? 1.06 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: backBM.containsMouse ? "#ffffff" : root.theme.textPrimary
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

                        // Discoverable pill toggle with hover & press
                        Rectangle {
                            height: 28
                            implicitWidth: discRow.implicitWidth + 20
                            radius: 14
                            visible: Services.SystemService.bluetoothEnabled
                            color: discHeaderMouse.pressed ? (Services.SystemService.bluetoothDiscoverable ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.16)) : (discHeaderMouse.containsMouse ? (Services.SystemService.bluetoothDiscoverable ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.12)) : (Services.SystemService.bluetoothDiscoverable ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)))
                            border.color: discHeaderMouse.containsMouse ? (Services.SystemService.bluetoothDiscoverable ? root.theme.accent : Qt.rgba(1, 1, 1, 0.25)) : (Services.SystemService.bluetoothDiscoverable ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.1))
                            border.width: 1
                            scale: discHeaderMouse.pressed ? 0.94 : (discHeaderMouse.containsMouse ? 1.04 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Row {
                                id: discRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: Services.SystemService.bluetoothDiscoverable ? "󰂰" : "󰂲"
                                    color: Services.SystemService.bluetoothDiscoverable ? root.theme.accent : (discHeaderMouse.containsMouse ? "#ffffff" : root.theme.textMuted)
                                    font.pixelSize: 12
                                    font.family: root.font
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: Services.SystemService.bluetoothDiscoverable ? "Visible" : "Hidden"
                                    color: Services.SystemService.bluetoothDiscoverable ? root.theme.textPrimary : (discHeaderMouse.containsMouse ? "#ffffff" : root.theme.textMuted)
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: discHeaderMouse
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.toggleBluetoothDiscoverable()
                            }
                        }

                        // Rescan button with rotation & hover/press scale
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            visible: Services.SystemService.bluetoothEnabled
                            color: rescBM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25) : (rescBM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                            border.color: rescBM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            scale: rescBM.pressed ? 0.90 : (rescBM.containsMouse ? 1.08 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                id: scanIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: Services.SystemService.bluetoothDiscovering ? root.theme.accentGreen : (rescBM.containsMouse ? "#ffffff" : root.theme.accent)
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
                            color: Services.SystemService.bluetoothEnabled ? (pwrSwMouse.containsMouse ? Qt.lighter(root.theme.accent, 1.1) : root.theme.accent) : (pwrSwMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.15))
                            scale: pwrSwMouse.pressed ? 0.94 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                color: "#ffffff"
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
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.1)
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
                                text: "Bluetooth is Turned Off"
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
                                color: turnOnM.pressed ? Qt.darker(root.theme.accent, 1.15) : (turnOnM.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)
                                scale: turnOnM.pressed ? 0.94 : (turnOnM.containsMouse ? 1.06 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Turn On"
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: turnOnM
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
                            spacing: 12

                            // ── MY DEVICES SECTION ────────────────
                            Text {
                                text: "MY DEVICES"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: Font.DemiBold
                                Layout.leftMargin: 2
                            }

                            // Empty Paired Placeholder
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 10
                                visible: Services.SystemService.bluetoothDevices.length === 0
                                color: Qt.rgba(1, 1, 1, 0.03)
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "No paired devices"
                                    color: root.theme.textMuted
                                    font.pixelSize: 11
                                    font.family: root.font
                                }
                            }

                            // Paired Devices List
                            Repeater {
                                model: Services.SystemService.bluetoothDevices

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    radius: 10
                                    color: pDevMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                    border.color: pDevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    scale: pDevMouse.pressed ? 0.985 : 1.0
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }
                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    // Whole row is clickable to connect / disconnect
                                    MouseArea {
                                        id: pDevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.connected) Services.SystemService.disconnectBluetooth(modelData.mac);
                                            else Services.SystemService.connectBluetooth(modelData.mac);
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        // Icon Container
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 8
                                            color: modelData.connected ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.18) : Qt.rgba(1, 1, 1, 0.08)

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getBtIcon(modelData.icon)
                                                color: modelData.connected ? root.theme.accentGreen : root.theme.accent
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        // Name & Details
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: modelData.name || modelData.mac
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            RowLayout {
                                                spacing: 6

                                                Text {
                                                    text: modelData.connected ? "Connected" : "Paired"
                                                    color: modelData.connected ? root.theme.accentGreen : root.theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                }

                                                // Battery badge if available
                                                Rectangle {
                                                    visible: modelData.battery !== null && modelData.battery !== undefined
                                                    height: 16
                                                    implicitWidth: battTxt.implicitWidth + 8
                                                    radius: 4
                                                    color: Qt.rgba(1, 1, 1, 0.08)

                                                    Text {
                                                        id: battTxt
                                                        anchors.centerIn: parent
                                                        text: "󰁹 " + (modelData.battery || 0) + "%"
                                                        color: root.theme.textPrimary
                                                        font.pixelSize: 9
                                                        font.family: root.font
                                                    }
                                                }
                                            }
                                        }

                                        // Connect / Disconnect button with tactile hover & scale
                                        Rectangle {
                                            height: 28
                                            implicitWidth: Math.max(76, connTxt.implicitWidth + 18)
                                            radius: 8
                                            color: modelData.connected ? (connBtnMouse.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.2) : Qt.rgba(1, 1, 1, 0.08)) : (connBtnMouse.containsMouse ? Qt.lighter(root.theme.accent, 1.15) : root.theme.accent)
                                            border.color: modelData.connected ? (connBtnMouse.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.45) : Qt.rgba(1, 1, 1, 0.15)) : (connBtnMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.35) : "transparent")
                                            border.width: 1
                                            scale: connBtnMouse.pressed ? 0.93 : (connBtnMouse.containsMouse ? 1.05 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                            Text {
                                                id: connTxt
                                                anchors.centerIn: parent
                                                text: modelData.connected ? (connBtnMouse.containsMouse ? "Disconnect" : "Connected") : "Connect"
                                                color: modelData.connected ? (connBtnMouse.containsMouse ? root.theme.accentRed : root.theme.textPrimary) : "#ffffff"
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: connBtnMouse
                                                anchors.fill: parent
                                                anchors.margins: -2
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.connected) Services.SystemService.disconnectBluetooth(modelData.mac);
                                                    else Services.SystemService.connectBluetooth(modelData.mac);
                                                }
                                            }
                                        }

                                        // Forget / Remove Device button with generous hit target & hover scale
                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: forgetMouse.pressed ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.35) : (forgetMouse.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.22) : Qt.rgba(1, 1, 1, 0.06))
                                            border.color: forgetMouse.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.5) : Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1
                                            scale: forgetMouse.pressed ? 0.88 : (forgetMouse.containsMouse ? 1.1 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰩹"
                                                color: forgetMouse.containsMouse ? root.theme.accentRed : root.theme.textMuted
                                                font.pixelSize: 13
                                                font.family: root.font
                                            }

                                            MouseArea {
                                                id: forgetMouse
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.removeBluetooth(modelData.mac)
                                            }
                                        }
                                    }
                                }
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
                                        text: "Searching..."
                                        color: root.theme.accent
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }

                                // Dedicated Scan Button Pill
                                Rectangle {
                                    visible: !Services.SystemService.bluetoothDiscovering
                                    height: 24
                                    implicitWidth: scanBtnTxt.implicitWidth + 20
                                    radius: 7
                                    color: scanBtnM.pressed ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3) : (scanBtnM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2) : Qt.rgba(1, 1, 1, 0.08))
                                    border.color: scanBtnM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.1)
                                    border.width: 1
                                    scale: scanBtnM.pressed ? 0.93 : (scanBtnM.containsMouse ? 1.05 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Text {
                                            text: "󰑐"
                                            color: scanBtnM.containsMouse ? "#ffffff" : root.theme.accent
                                            font.pixelSize: 11
                                            font.family: root.font
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            id: scanBtnTxt
                                            text: "Scan"
                                            color: scanBtnM.containsMouse ? "#ffffff" : root.theme.accent
                                            font.pixelSize: 10
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: scanBtnM
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.SystemService.startBluetoothScan()
                                    }
                                }
                            }

                            // Empty Available Placeholder
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Services.SystemService.bluetoothDiscovering ? 46 : 54
                                radius: 10
                                visible: Services.SystemService.bluetoothAvailableDevices.length === 0
                                color: Qt.rgba(1, 1, 1, 0.03)
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    visible: !Services.SystemService.bluetoothDiscovering

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "No nearby devices found"
                                        color: root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Tap Scan above to search for nearby accessories."
                                        color: Qt.rgba(1, 1, 1, 0.35)
                                        font.pixelSize: 9
                                        font.family: root.font
                                    }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    visible: Services.SystemService.bluetoothDiscovering

                                    Text {
                                        text: "󰑐"
                                        color: root.theme.accent
                                        font.pixelSize: 12
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                        NumberAnimation on rotation {
                                            running: Services.SystemService.bluetoothDiscovering
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 360
                                            duration: 900
                                        }
                                    }

                                    Text {
                                        text: "Searching for nearby devices..."
                                        color: root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            // Discovered Available Devices List
                            Repeater {
                                model: Services.SystemService.bluetoothAvailableDevices

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 48
                                    radius: 10
                                    color: aDevMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                    border.color: aDevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Services.Aesthetic.innerCardBorder
                                    border.width: 1
                                    scale: aDevMouse.pressed ? 0.985 : 1.0
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }
                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    // Whole row is clickable to pair
                                    MouseArea {
                                        id: aDevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.SystemService.pairBluetooth(modelData.mac)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        Rectangle {
                                            width: 28
                                            height: 28
                                            radius: 7
                                            color: Qt.rgba(1, 1, 1, 0.08)

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getBtIcon(modelData.icon)
                                                color: root.theme.accent
                                                font.pixelSize: 13
                                                font.family: root.font
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: modelData.name || modelData.mac
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
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

                                        // Pair button with tactile hover & scale
                                        Rectangle {
                                            height: 28
                                            implicitWidth: Math.max(68, pairTxt.implicitWidth + 18)
                                            radius: 8
                                            color: pairBtnMouse.pressed ? Qt.darker(root.theme.accent, 1.15) : (pairBtnMouse.containsMouse ? root.theme.accent : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2))
                                            border.color: pairBtnMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.4) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.4)
                                            border.width: 1
                                            scale: pairBtnMouse.pressed ? 0.93 : (pairBtnMouse.containsMouse ? 1.05 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                            Text {
                                                id: pairTxt
                                                anchors.centerIn: parent
                                                text: "Pair"
                                                color: pairBtnMouse.containsMouse ? "#ffffff" : root.theme.accent
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: pairBtnMouse
                                                anchors.fill: parent
                                                anchors.margins: -2
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

                    // ── NATIVE FOOTER: ADAPTER DISCOVERABILITY ─────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        visible: Services.SystemService.bluetoothEnabled
                        color: footerCardM.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.04)
                        border.color: footerCardM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
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
                                implicitWidth: footerDiscTxt.implicitWidth + 14
                                radius: 12
                                color: Services.SystemService.bluetoothDiscoverable ? (footerCardM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3) : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2)) : (footerCardM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08))
                                border.color: Services.SystemService.bluetoothDiscoverable ? (footerCardM.containsMouse ? root.theme.accent : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.4)) : (footerCardM.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.1))
                                border.width: 1
                                scale: footerCardM.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                Text {
                                    id: footerDiscTxt
                                    anchors.centerIn: parent
                                    text: Services.SystemService.bluetoothDiscoverable ? "Visible" : "Hidden"
                                    color: Services.SystemService.bluetoothDiscoverable ? root.theme.accent : (footerCardM.containsMouse ? "#ffffff" : root.theme.textMuted)
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
                    visible: root.activeView === "audio"
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
                            color: backAudioM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Behavior on color { ColorAnimation { duration: 120 } }

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
                            color: rescAudioM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }
                            MouseArea {
                                id: rescAudioM
                                anchors.fill: parent
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
                        contentHeight: audioDetailCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: audioDetailCol
                            width: parent.width
                            spacing: 12

                            // ── OUTPUT CARD ──
                            Rectangle {
                                Layout.fillWidth: true
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
                                            color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.theme.textMuted
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Services.SystemService.volumeMuted ? Font.DemiBold : Font.Normal
                                        }
                                    }

                                    // Sound Slider Capsule
                                    Rectangle {
                                        id: subSoundBar
                                        Layout.fillWidth: true
                                        height: 32
                                        radius: 16
                                        color: Services.SystemService.volumeMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                        border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (subSoundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                        border.width: 1
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.volumeIcon
                                            color: Services.SystemService.volumeMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }

                                        Rectangle {
                                            id: subSoundFill
                                            width: (Services.SystemService.volumeMuted || Services.SystemService.volume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))
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
                                                color: Services.SystemService.volumeMuted ? "#ffffff" : root.theme.onPrimary
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

                                    // Sinks List
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                        }

                                        Repeater {
                                            model: Services.SystemService.audioSinks
                                            Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 32
                                                radius: 8
                                                color: modelData.active ? Qt.rgba(0, 0.48, 1, 0.25) : (sinkRowSubM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 8

                                                    Text {
                                                        text: {
                                                            const nm = modelData.name.toLowerCase();
                                                            if (nm.includes("hdmi")) return "󰡁";
                                                            if (nm.includes("headphone") || nm.includes("headset") || nm.includes("airpod") || nm.includes("buds") || nm.includes("earphone") || nm.includes("bluez")) return "󰋋";
                                                            return "󰓃";
                                                        }
                                                        color: modelData.active ? root.theme.accent : root.theme.textPrimary
                                                        font.pixelSize: 14
                                                        font.family: root.font
                                                    }

                                                    Text {
                                                        text: modelData.name.replace("Alder Lake PCH-P High Definition Audio Controller ", "")
                                                        color: modelData.active ? "#ffffff" : root.theme.textPrimary
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

                                                MouseArea {
                                                    id: sinkRowSubM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Services.SystemService.setAudioSink(modelData.id)
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
                                            text: Services.SystemService.appAudioStreams.length > 0 
                                                ? (Services.SystemService.appAudioStreams.length + " active")
                                                : "None"
                                            color: root.theme.textMuted
                                            font.pixelSize: 10
                                            font.family: root.font
                                        }
                                    }

                                    // Empty State
                                    Rectangle {
                                        visible: Services.SystemService.appAudioStreams.length === 0
                                        Layout.fillWidth: true
                                        height: 38
                                        radius: 10
                                        color: Qt.rgba(1, 1, 1, 0.03)

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8

                                            Text {
                                                text: "󰝚"
                                                color: Qt.rgba(1, 1, 1, 0.3)
                                                font.pixelSize: 13
                                                font.family: root.font
                                            }

                                            Text {
                                                text: "No applications currently playing audio"
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                            }
                                        }
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

                            // ── INPUT (MICROPHONE) CARD: CLICK TO EXPAND & CHANGE VOL ──
                            Rectangle {
                                id: micCard
                                Layout.fillWidth: true
                                implicitHeight: micCardCol.implicitHeight + 20
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                clip: true
                                Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                ColumnLayout {
                                    id: micCardCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    // Expandable Header Button (Entire row clickable to expand/collapse)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 36
                                        radius: 10
                                        color: micExpBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Rectangle {
                                                width: 24
                                                height: 24
                                                radius: 12
                                                color: Services.SystemService.micMuted
                                                    ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.2)
                                                    : (Services.SystemService.micInUse ? Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                                                    color: Services.SystemService.micMuted ? root.theme.accentRed : (Services.SystemService.micInUse ? root.theme.accentOrange : "#ffffff")
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                }
                                            }

                                            Text {
                                                text: "Microphone"
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: Services.SystemService.micMuted ? "Muted" : Services.SystemService.micVolume + "%"
                                                color: Services.SystemService.micMuted ? root.theme.accentRed : root.theme.textMuted
                                                font.pixelSize: 11
                                                font.family: root.font
                                                font.weight: Services.SystemService.micMuted ? Font.DemiBold : Font.Normal
                                            }

                                            Text {
                                                text: "›"
                                                color: root.soundInputsOpen ? root.theme.accent : root.theme.textMuted
                                                font.pixelSize: 15
                                                font.family: root.font
                                                rotation: root.soundInputsOpen ? 90 : 0
                                                Behavior on rotation { NumberAnimation { duration: 140 } }
                                            }
                                        }

                                        MouseArea {
                                            id: micExpBtnM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.soundInputsOpen = !root.soundInputsOpen;
                                                if (root.soundInputsOpen) Services.SystemService.rescanAudioSources();
                                            }
                                        }
                                    }

                                    // Expandable Content: Mic Volume Slider & Sources List
                                    ColumnLayout {
                                        visible: root.soundInputsOpen
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                        }

                                        // Mic Volume Slider
                                        Rectangle {
                                            id: subMicBar
                                            Layout.fillWidth: true
                                            height: 32
                                            radius: 16
                                            color: Services.SystemService.micMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                            border.color: Services.SystemService.micMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (subMicMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                            border.width: 1
                                            clip: true
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            Text {
                                                x: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                                                color: Services.SystemService.micMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }

                                             Rectangle {
                                                id: subMicFill
                                                width: (Services.SystemService.micMuted || Services.SystemService.micVolume <= 0) ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Math.min(100, Services.SystemService.micVolume) / 100)))
                                                height: parent.height
                                                radius: 16
                                                color: Services.SystemService.micMuted ? root.theme.accentRed : (Services.SystemService.micInUse ? "#ff9f0a" : root.theme.accent)
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
                                                    color: (Services.SystemService.micMuted || Services.SystemService.micInUse) ? "#ffffff" : root.theme.onPrimary
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

                                        // Input Sources List
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                text: "Input Devices"
                                                color: root.theme.textMuted
                                                font.pixelSize: 10
                                                font.family: root.font
                                                font.weight: Font.Medium
                                                anchors.leftMargin: 4
                                            }

                                            Repeater {
                                                model: Services.SystemService.audioSources
                                                Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: 32
                                                    radius: 8
                                                    color: modelData.active ? Qt.rgba(0, 0.48, 1, 0.25) : (sourceRowSubM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 8

                                                        Text {
                                                            text: modelData.name.toLowerCase().includes("headset") || modelData.name.toLowerCase().includes("headphone") ? "󰋎" : "󰍬"
                                                            color: modelData.active ? root.theme.accent : root.theme.textPrimary
                                                            font.pixelSize: 13
                                                            font.family: root.font
                                                        }

                                                        Text {
                                                            text: modelData.name.replace("Alder Lake PCH-P High Definition Audio Controller ", "")
                                                            color: modelData.active ? "#ffffff" : root.theme.textPrimary
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

                                                    MouseArea {
                                                        id: sourceRowSubM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Services.SystemService.setAudioSource(modelData.id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Footer: Sound Settings shortcut
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 10
                                color: openAudioSM.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

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
                                        text: "Sound Settings..."
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
                                    onClicked: {
                                        Services.SystemService.runCmd("pavucontrol || systemsettings kcm_pulseaudio");
                                        Services.SystemService.controlCenterOpen = false;
                                    }
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
                        contentHeight: dispCol.implicitHeight + 20
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
                // VIEW 4: WALLPAPER GALLERY & CONTROLS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    visible: root.activeView === "wallpaper"
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
                            color: backWallM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backWallM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Wallpapers"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Shuffle Button
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: randWallM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "󰘚"
                                color: root.theme.textPrimary
                                font.pixelSize: 15
                                font.family: root.font
                            }
                            MouseArea {
                                id: randWallM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.WallpaperService.randomWallpaper()
                            }
                        }
                    }

                    // Wallpapers Grid View
                    GridView {
                        id: wallGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: width / 2
                        cellHeight: 110
                        model: Services.WallpaperService.wallpapers

                        delegate: Item {
                            required property string modelData
                            width: wallGrid.cellWidth
                            height: wallGrid.cellHeight

                            readonly property bool isCurrent: {
                                const clean = Services.WallpaperService.currentWallpaper.replace(/^file:\/\//, "");
                                return clean === modelData;
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 10
                                clip: true
                                color: Qt.rgba(0, 0, 0, 0.3)
                                border.color: isCurrent ? root.theme.accent : (gridTileM.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.08))
                                border.width: isCurrent ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 180
                                    sourceSize.height: 110
                                }

                                // Gradient overlay at bottom for title
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 26
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 4
                                        text: Services.WallpaperService.extractName(modelData)
                                        color: "#ffffff"
                                        font.pixelSize: 10
                                        font.family: root.font
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                }

                                // Active checkmark badge
                                Rectangle {
                                    visible: isCurrent
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: root.theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: gridTileM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.WallpaperService.setWallpaper(modelData)
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 5: NOTIFICATION CENTER INTEGRATED TAB
                // ═══════════════════════════════════════════
                Item {
                    id: notificationsView
                    visible: Services.SystemService.controlCenterTab === "notifications" && root.activeView === "main"
                    anchors.top: tabSegmentedBar.bottom
                    anchors.topMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        // Header Bar: "Notification Center" | DND Pill | "Clear All"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Notification Center"
                                color: root.theme.textPrimary
                                font.pixelSize: 13
                                font.family: root.font
                                font.weight: Font.Bold
                            }

                            Item { Layout.fillWidth: true }

                            // DND Pill
                            Rectangle {
                                implicitHeight: 24
                                implicitWidth: dndPillRow.implicitWidth + 12
                                radius: 12
                                color: Services.NotificationService.dnd ? "#5856d6" : Qt.rgba(1, 1, 1, 0.10)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    id: dndPillRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: Services.NotificationService.dnd ? "󰂛" : "󰂚"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.family: root.font
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: Services.NotificationService.dnd ? "DND On" : "DND"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: Font.Medium
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.NotificationService.toggleDnd()
                                }
                            }

                            // Clear All Button
                            Rectangle {
                                implicitHeight: 24
                                implicitWidth: clearAllText.implicitWidth + 14
                                radius: 12
                                color: clearAllMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                visible: Services.NotificationService.unreadCount > 0
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    id: clearAllText
                                    anchors.centerIn: parent
                                    text: "Clear All"
                                    color: root.theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: clearAllMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.NotificationService.clearAll()
                                }
                            }
                        }

                        // Notifications List or Empty State
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Empty State
                            Column {
                                anchors.centerIn: parent
                                spacing: 10
                                visible: Services.NotificationService.unreadCount === 0

                                Rectangle {
                                    width: 56
                                    height: 56
                                    radius: 28
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰂚"
                                        color: root.theme.textMuted
                                        font.pixelSize: 28
                                        font.family: root.font
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No Notifications"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 14
                                    font.family: root.font
                                    font.weight: Font.Bold
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "You're completely caught up"
                                    color: root.theme.textMuted
                                    font.pixelSize: 11
                                    font.family: root.font
                                }
                            }

                            // Active Notifications List
                            Flickable {
                                anchors.fill: parent
                                contentHeight: notifCol.implicitHeight + 10
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                visible: Services.NotificationService.unreadCount > 0

                                ColumnLayout {
                                    id: notifCol
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: Services.NotificationService.server.trackedNotifications

                                        Rectangle {
                                            id: notifCard
                                            required property var modelData
                                            required property int index

                                            Layout.fillWidth: true
                                            implicitHeight: notifCardCol.implicitHeight + 20
                                            radius: 14
                                            color: Services.Aesthetic.innerCardBg
                                            border.color: Services.Aesthetic.innerCardBorder
                                            border.width: 1

                                            ColumnLayout {
                                                id: notifCardCol
                                                width: parent.width - 20
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.top: parent.top
                                                anchors.topMargin: 10
                                                spacing: 6

                                                // App Header & Dismiss Button
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Item {
                                                        width: 16
                                                        height: 16
                                                        Layout.alignment: Qt.AlignVCenter

                                                        IconImage {
                                                            id: listAppIcon
                                                            anchors.fill: parent
                                                            source: Quickshell.iconPath(notifCard.modelData.appIcon ?? "", true)
                                                            visible: (notifCard.modelData.appIcon ?? "") !== "" && status === Image.Ready
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰂚"
                                                            color: root.theme.accent
                                                            font.pixelSize: 12
                                                            font.family: root.font
                                                            visible: !listAppIcon.visible
                                                        }
                                                    }

                                                    Text {
                                                        text: (notifCard.modelData.appName && notifCard.modelData.appName.length > 0 ? notifCard.modelData.appName : "NOTIFICATION").toUpperCase()
                                                        color: root.theme.textMuted
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                        font.weight: Font.Bold
                                                        font.letterSpacing: 0.5
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    // Dismiss Button
                                                    Rectangle {
                                                        width: 18
                                                        height: 18
                                                        radius: 9
                                                        color: dismissMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                                                        Layout.alignment: Qt.AlignVCenter

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "✕"
                                                            color: root.theme.textSecondary
                                                            font.pixelSize: 9
                                                            font.bold: true
                                                        }

                                                        MouseArea {
                                                            id: dismissMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                Services.NotificationService.dismiss(notifCard.modelData);
                                                            }
                                                        }
                                                    }
                                                }

                                                // Notification Content
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: notifCard.modelData.summary ?? ""
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    font.weight: Font.Bold
                                                    wrapMode: Text.Wrap
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: notifCard.modelData.body ?? ""
                                                    color: Qt.rgba(0.9, 0.9, 0.95, 0.85)
                                                    font.pixelSize: 11
                                                    font.family: root.font
                                                    wrapMode: Text.Wrap
                                                    maximumLineCount: 4
                                                    elide: Text.ElideRight
                                                    visible: (notifCard.modelData.body ?? "").length > 0
                                                }

                                                // Action Buttons (if any)
                                                Row {
                                                    spacing: 6
                                                    visible: notifCard.modelData.actions && notifCard.modelData.actions.length > 0
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: 2

                                                    Repeater {
                                                        model: notifCard.modelData.actions

                                                        Rectangle {
                                                            id: notifCardActBtn
                                                            required property var modelData
                                                            height: 22
                                                            implicitWidth: notifCardActText.implicitWidth + 14
                                                            radius: 6
                                                            color: notifCardActMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)

                                                            Text {
                                                                id: notifCardActText
                                                                anchors.centerIn: parent
                                                                text: notifCardActBtn.modelData.text
                                                                color: "#ffffff"
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                                font.weight: Font.Medium
                                                            }

                                                            MouseArea {
                                                                id: notifCardActMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    notifCardActBtn.modelData.invoke();
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
