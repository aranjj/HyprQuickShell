import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    // Sub-view toggle: "main", "wifi", "bluetooth", "media", "wallpaper"
    readonly property string activeView: Services.SystemService.controlCenterSubView

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            Services.SystemService.toggleControlCenter();
        }

        function open(): void {
            Services.SystemService.openControlCenter("controls", "main");
        }

        function close(): void {
            Services.SystemService.controlCenterOpen = false;
        }
    }

    // Quick toggles states
    property bool dndEnabled: false
    property bool nightShiftEnabled: false
    property bool soundOutputsOpen: false
    property bool soundInputsOpen: false

    // Preferred MPRIS player identity
    property string preferredPlayerIdentity: ""

    // Active MPRIS player helper
    property var activePlayer: {
        const players = Mpris.players.values;
        if (!players || players.length === 0) return null;
        if (preferredPlayerIdentity) {
            for (let i = 0; i < players.length; i++) {
                if (players[i].identity === preferredPlayerIdentity) return players[i];
            }
        }
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
        return players[0];
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

            visible: Services.SystemService.controlCenterOpen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-control-center"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: card }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // Click backdrop to dismiss
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
                width: 370
                height: 640
                anchors.top: parent.top
                anchors.topMargin: 44
                anchors.right: parent.right
                anchors.rightMargin: 14
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

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
                    height: 32
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1

                    // Sliding Pill Indicator
                    Rectangle {
                        id: tabIndicator
                        width: (parent.width - 6) / 2
                        height: 26
                        radius: 8
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
                                }

                                Text {
                                    text: "Notifications" + (Services.NotificationService.unreadCount > 0 ? " (" + Services.NotificationService.unreadCount + ")" : "")
                                    color: Services.SystemService.controlCenterTab === "notifications" ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Services.SystemService.controlCenterTab === "notifications" ? Font.Bold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
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
                                Layout.preferredWidth: 196
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
                                        implicitHeight: 36
                                        radius: 10
                                        color: wifiRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Rectangle {
                                                width: 28
                                                height: 28
                                                radius: 14
                                                color: Services.SystemService.wifiEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.12)
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰖩"
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
                                                    font.pixelSize: 11
                                                    font.family: root.font
                                                    font.weight: Font.DemiBold
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: Services.SystemService.wifiEnabled ? (Services.SystemService.wifiSsid || "Not Connected") : "Off"
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
                                        implicitHeight: 36
                                        radius: 10
                                        color: btRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Rectangle {
                                                width: 28
                                                height: 28
                                                radius: 14
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
                                                    font.pixelSize: 11
                                                    font.family: root.font
                                                    font.weight: Font.DemiBold
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: Services.SystemService.bluetoothEnabled ? (Services.SystemService.bluetoothDevices.length > 0 ? (Services.SystemService.bluetoothDevices[0].name || "Connected") : "On") : "Off"
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
                                                Services.SystemService.rescanBluetooth();
                                                Services.SystemService.controlCenterSubView = "bluetooth";
                                            }
                                        }
                                    }

                                    // AirDrop / LocalSend Row
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: 10
                                        color: shareRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Rectangle {
                                                width: 28
                                                height: 28
                                                radius: 14
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
                                                    font.pixelSize: 11
                                                    font.family: root.font
                                                    font.weight: Font.DemiBold
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: "LocalSend"
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
                                Layout.preferredWidth: 142
                                Layout.minimumWidth: 142
                                Layout.maximumWidth: 142
                                implicitHeight: 140
                                radius: 16
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 0

                                    // Top Header: Thumbnail + Track Info + Cava Waveform + Expand Chevron
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Thumbnail / Art (50x50, radius 12)
                                        Rectangle {
                                            width: 50
                                            height: 50
                                            radius: 12
                                            clip: true
                                            color: Qt.rgba(0, 0, 0, 0.3)
                                            border.color: Qt.rgba(1, 1, 1, 0.12)
                                            border.width: 1
                                            Layout.alignment: Qt.AlignVCenter

                                            Image {
                                                id: ccIosThumb
                                                anchors.fill: parent
                                                source: root.activePlayer?.trackArtUrl ?? ""
                                                fillMode: Image.PreserveAspectCrop
                                                visible: status === Image.Ready && source != ""
                                                asynchronous: true
                                                cache: true
                                                sourceSize.width: 100
                                                sourceSize.height: 100
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰝚"
                                                color: "#fa2d48"
                                                font.pixelSize: 22
                                                font.family: root.font
                                                visible: !ccIosThumb.visible
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.controlCenterSubView = "media"
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
                                                font.pixelSize: 11
                                                font.family: root.font
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: root.activePlayer?.trackArtist || ""
                                                color: root.theme.textMuted
                                                font.pixelSize: 9
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
                                            color: root.theme.textMuted
                                            font.pixelSize: 16
                                            font.family: root.font
                                            Layout.alignment: Qt.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemService.controlCenterSubView = "media"
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillHeight: true
                                    }

                                    // Bottom Playback Controls: ⏮  ⏯  ⏭
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 0

                                        Item {
                                            width: 28
                                            height: 28
                                            Layout.alignment: Qt.AlignVCenter

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 14
                                                color: prevIosM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
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

                                        // Play / Pause Circle Button (iOS Style)
                                        Rectangle {
                                            width: 36
                                            height: 36
                                            radius: 18
                                            color: playIosM.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : (root.isMediaPlaying ? root.playerAccent : Qt.rgba(1, 1, 1, 0.15))
                                            Layout.alignment: Qt.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: root.isMediaPlaying ? 0 : 1
                                                text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                                color: "#ffffff"
                                                font.pixelSize: 17
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

                                        Item {
                                            width: 28
                                            height: 28
                                            Layout.alignment: Qt.AlignVCenter

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 14
                                                color: nextIosM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
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
                                implicitHeight: 50
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
                                        width: 28
                                        height: 28
                                        radius: 14
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.NotificationService.dnd ? "On" : "Off"
                                            color: Services.NotificationService.dnd ? root.theme.accentMauve : root.theme.textMuted
                                            font.pixelSize: 9
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
                                implicitHeight: 50
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
                                        width: 28
                                        height: 28
                                        radius: 14
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.NightLightService.active ? "3000K" : "Off"
                                            color: Services.NightLightService.active ? root.theme.accentOrange : root.theme.textMuted
                                            font.pixelSize: 9
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
                                implicitHeight: 50
                                radius: 14
                                color: caffeineMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.SystemService.caffeineActive ? Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.45) : Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Services.SystemService.caffeineActive ? root.theme.accentYellow : Qt.rgba(1, 1, 1, 0.12)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅶"
                                            color: Services.SystemService.caffeineActive ? "#000000" : root.theme.textMuted
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.SystemService.caffeineActive ? "Active" : "Off"
                                            color: Services.SystemService.caffeineActive ? "#ffb340" : root.theme.textMuted
                                            font.pixelSize: 9
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
                            implicitHeight: 74
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
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Services.SystemService.brightness + "%"
                                        color: root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                    }
                                }

                                // Modern macOS Tahoe Capsule Slider Track
                                Rectangle {
                                    id: brightBar
                                    Layout.fillWidth: true
                                    height: 30
                                    radius: 15
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
                                        width: Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.brightness / 100)))
                                        height: parent.height
                                        radius: 15
                                        color: Services.Aesthetic.sliderFill
                                        clip: true
                                        Behavior on width { NumberAnimation { duration: 50 } }

                                        // Foreground Dark Glyph (uncovered smoothly as fill expands)
                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.brightness <= 33 ? "󰃞" : (Services.SystemService.brightness <= 66 ? "󰃟" : "󰃠")
                                            color: "#16161a"
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    MouseArea {
                                        id: brightMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => {
                                            const pct = Math.max(1, Math.min(100, Math.round((mouse.x / brightBar.width) * 100)));
                                            Services.SystemService.setBrightnessPercent(pct);
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (pressed) {
                                                const pct = Math.max(1, Math.min(100, Math.round((mouse.x / brightBar.width) * 100)));
                                                Services.SystemService.setBrightnessPercent(pct);
                                            }
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
                            implicitHeight: 74
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
                                        font.pixelSize: 11
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
                                    // Audio Detail Page Chevron Button
                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
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
                                    height: 30
                                    radius: 15
                                    color: Services.SystemService.volumeMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                    border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (soundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                    border.width: 1
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    // Background Unfilled Glyph
                                    Text {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Services.SystemService.volumeMuted ? "󰖁"
                                            : (Services.SystemService.volume === 0 ? "󰖁"
                                            : (Services.SystemService.volume <= 33 ? "󰕿"
                                            : (Services.SystemService.volume <= 66 ? "󰖀" : "󰕾")))
                                        color: Services.SystemService.volumeMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }

                                    // Dynamic Filled Capsule (with dual-layer clipped dark glyph)
                                    Rectangle {
                                        id: soundFill
                                        width: Services.SystemService.volumeMuted ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))
                                        height: parent.height
                                        radius: 15
                                        color: Services.Aesthetic.sliderFill
                                        clip: true
                                        Behavior on width { NumberAnimation { duration: 50 } }

                                        // Foreground Dark Glyph
                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.volumeMuted ? "󰖁"
                                                : (Services.SystemService.volume === 0 ? "󰖁"
                                                : (Services.SystemService.volume <= 33 ? "󰕿"
                                                : (Services.SystemService.volume <= 66 ? "󰖀" : "󰕾")))
                                            color: "#16161a"
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                    }

                                    MouseArea {
                                        id: soundMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => {
                                            if (mouse.x < 28) {
                                                Services.SystemService.toggleMute();
                                            } else {
                                                const pct = Math.max(0, Math.min(100, Math.round((mouse.x / soundBar.width) * 100)));
                                                Services.SystemService.setVolumePercent(pct);
                                            }
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (pressed) {
                                                const pct = Math.max(0, Math.min(100, Math.round((mouse.x / soundBar.width) * 100)));
                                                Services.SystemService.setVolumePercent(pct);
                                            }
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
                                implicitHeight: 50
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
                                        width: 28
                                        height: 28
                                        radius: 14
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Screenshot"
                                            color: root.theme.textMuted
                                            font.pixelSize: 9
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
                                        Services.SystemService.controlCenterOpen = false;
                                        Services.ScreenshotService.toggleToolbar();
                                    }
                                }
                            }

                            // 2. Power Profile Cycle Pill
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 50
                                radius: 14
                                color: powerTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Services.SystemService.powerProfile === "performance" ? root.theme.accentOrange
                                             : Services.SystemService.powerProfile === "power-saver" ? root.theme.accentGreen : root.theme.accent
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.SystemService.powerProfile === "performance" ? "󰓅"
                                                : Services.SystemService.powerProfile === "power-saver" ? "󰌪" : "󰾅"
                                            color: Services.SystemService.powerProfile === "performance" || Services.SystemService.powerProfile === "power-saver" ? "#000000" : "#ffffff"
                                            font.pixelSize: 13
                                            font.family: root.font
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "Profile"
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.SystemService.powerProfile === "performance" ? "Performance"
                                                : Services.SystemService.powerProfile === "power-saver" ? "Power Saver" : "Balanced"
                                            color: root.theme.textMuted
                                            font.pixelSize: 9
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: powerTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = Services.SystemService.powerProfile;
                                        const next = p === "performance" ? "balanced" : (p === "balanced" ? "power-saver" : "performance");
                                        Services.SystemService.setPowerProfile(next);
                                    }
                                }
                            }

                            // 3. Power Menu Tile (replaces wallpaper changer)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 50
                                radius: 14
                                color: powerMenuTileMouse.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Menu"
                                            color: root.theme.textMuted
                                            font.pixelSize: 9
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
                                implicitHeight: 50
                                radius: 14
                                color: Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
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
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: Services.SystemService.batteryCharging ? "Charging" : (Services.SystemService.batteryPlugged ? "AC Connected" : "Battery")
                                            color: root.theme.textMuted
                                            font.pixelSize: 9
                                            font.family: root.font
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            // CPU & RAM Card (Click -> btop)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 50
                                radius: 14
                                color: sysStatsM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Qt.rgba(1, 1, 1, 0.08)

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
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            text: "CPU " + Services.SystemService.cpuUsage + "  •  RAM " + Services.SystemService.memUsage
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Activity Monitor"
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
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }
                                }

                                MouseArea {
                                    id: sysStatsM
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

                // ═══════════════════════════════════════════
                // VIEW 2: macOS STYLE NATIVE WI-FI DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    visible: root.activeView === "wifi"
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
                            color: backWM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: root.theme.textPrimary
                                font.pixelSize: 18
                                font.family: root.font
                            }
                            MouseArea {
                                id: backWM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.controlCenterSubView = "main"
                            }
                        }

                        Text {
                            text: "Wi-Fi"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Rescan button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: rescWM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }
                            MouseArea {
                                id: rescWM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.rescanWifi()
                            }
                        }

                        // Switch
                        Rectangle {
                            width: 44
                            height: 24
                            radius: 12
                            color: Services.SystemService.wifiEnabled ? root.theme.accentGreen : Qt.rgba(1, 1, 1, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }

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
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.toggleWifi()
                            }
                        }
                    }

                    // Connected Network Tile
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 12
                        color: Services.Aesthetic.innerCardBg
                        border.color: Services.Aesthetic.innerCardBorder
                        border.width: 1
                        visible: Services.SystemService.wifiEnabled && Services.SystemService.wifiSsid !== ""

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Text {
                                text: "󰖩"
                                color: root.theme.accentGreen
                                font.pixelSize: 16
                                font.family: root.font
                            }

                            Column {
                                Layout.fillWidth: true
                                Text {
                                    text: "Connected Network"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                }
                                Text {
                                    text: Services.SystemService.wifiSsid
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                width: 74
                                height: 26
                                radius: 8
                                color: disconM.containsMouse ? "#ff453a" : Qt.rgba(1, 1, 1, 0.1)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Disconnect"
                                    color: disconM.containsMouse ? "#ffffff" : root.theme.textPrimary
                                    font.pixelSize: 10
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: disconM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemService.disconnectWifi()
                                }
                            }
                        }
                    }

                    Text {
                        text: "Known & Nearby Networks"
                        color: root.theme.textMuted
                        font.pixelSize: 11
                        font.family: root.font
                        font.weight: Font.Medium
                        anchors.leftMargin: 4
                    }

                    // Network List
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: Services.SystemService.wifiNetworks

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 44
                            radius: 10
                            color: wifiItmM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: modelData.bars || "▂▄▆█"
                                    color: modelData.active ? root.theme.accentGreen : root.theme.accent
                                    font.pixelSize: 11
                                    font.family: root.font
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.ssid
                                        color: modelData.active ? root.theme.accentGreen : root.theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: modelData.active ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        width: 180
                                    }
                                    Text {
                                        text: modelData.security || "Open"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }

                                Rectangle {
                                    width: 60
                                    height: 24
                                    radius: 6
                                    color: modelData.active ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.active ? "Active" : "Connect"
                                        color: modelData.active ? root.theme.accentGreen : root.theme.accent
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }
                            }

                            MouseArea {
                                id: wifiItmM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!modelData.active) {
                                        Services.SystemService.connectWifi(modelData.ssid);
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 3: macOS STYLE BLUETOOTH DETAILS
                // ═══════════════════════════════════════════
                ColumnLayout {
                    visible: root.activeView === "bluetooth"
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
                            color: backBM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
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

                        // Rescan button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: rescBM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }
                            MouseArea {
                                id: rescBM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.rescanBluetooth()
                            }
                        }

                        // Switch
                        Rectangle {
                            width: 44
                            height: 24
                            radius: 12
                            color: Services.SystemService.bluetoothEnabled ? root.theme.accent : Qt.rgba(1, 1, 1, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }

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
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.toggleBluetooth()
                            }
                        }
                    }

                    Text {
                        text: "Devices"
                        color: root.theme.textMuted
                        font.pixelSize: 11
                        font.family: root.font
                        font.weight: Font.Medium
                        anchors.leftMargin: 4
                    }

                    // Device List
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: Services.SystemService.bluetoothDevices

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 46
                            radius: 10
                            color: btItmM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: "󰂯"
                                    color: modelData.connected ? root.theme.accentGreen : root.theme.accent
                                    font.pixelSize: 16
                                    font.family: root.font
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.name || modelData.mac
                                        color: modelData.connected ? root.theme.accentGreen : root.theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        width: 180
                                    }
                                    Text {
                                        text: modelData.mac
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }

                                Rectangle {
                                    width: 72
                                    height: 24
                                    radius: 6
                                    color: modelData.connected ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.connected ? "Connected" : "Connect"
                                        color: modelData.connected ? root.theme.accentGreen : root.theme.accent
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }
                            }

                            MouseArea {
                                id: btItmM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.connected) Services.SystemService.disconnectBluetooth(modelData.mac);
                                    else Services.SystemService.connectBluetooth(modelData.mac);
                                }
                            }
                        }

                        // Empty placeholder
                        Text {
                            anchors.centerIn: parent
                            visible: Services.SystemService.bluetoothDevices.length === 0
                            text: Services.SystemService.bluetoothEnabled ? "No paired devices found\nTurn on device pairing to connect" : "Bluetooth is turned off"
                            color: root.theme.textMuted
                            font.pixelSize: 12
                            font.family: root.font
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Open Full Bluetooth Settings
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 10
                        color: openBtSM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰂱"
                                color: root.theme.accent
                                font.pixelSize: 14
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Bluetooth Settings..."
                                color: root.theme.textPrimary
                                font.pixelSize: 11
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: openBtSM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.SystemService.runCmd("systemsettings kcm_bluetooth || blueman-manager");
                                Services.SystemService.controlCenterOpen = false;
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
                            width: 28
                            height: 28
                            radius: 14
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
                                        height: 30
                                        radius: 15
                                        color: Services.SystemService.volumeMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                        border.color: Services.SystemService.volumeMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (subSoundMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                        border.width: 1
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Behavior on border.color { ColorAnimation { duration: 120 } }

                                        Text {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Services.SystemService.volumeMuted ? "󰖁"
                                                : (Services.SystemService.volume === 0 ? "󰖁"
                                                : (Services.SystemService.volume <= 33 ? "󰕿"
                                                : (Services.SystemService.volume <= 66 ? "󰖀" : "󰕾")))
                                            color: Services.SystemService.volumeMuted ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.45)
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }

                                        Rectangle {
                                            id: subSoundFill
                                            width: Services.SystemService.volumeMuted ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))
                                            height: parent.height
                                            radius: 15
                                            color: Services.Aesthetic.sliderFill
                                            clip: true
                                            Behavior on width { NumberAnimation { duration: 50 } }

                                            Text {
                                                x: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Services.SystemService.volumeMuted ? "󰖁"
                                                    : (Services.SystemService.volume === 0 ? "󰖁"
                                                    : (Services.SystemService.volume <= 33 ? "󰕿"
                                                    : (Services.SystemService.volume <= 66 ? "󰖀" : "󰕾")))
                                                color: "#16161a"
                                                font.pixelSize: 15
                                                font.family: root.font
                                            }
                                        }

                                        MouseArea {
                                            id: subSoundMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: (mouse) => {
                                                if (mouse.x < 28) {
                                                    Services.SystemService.toggleMute();
                                                } else {
                                                    const pct = Math.max(0, Math.min(100, Math.round((mouse.x / subSoundBar.width) * 100)));
                                                    Services.SystemService.setVolumePercent(pct);
                                                }
                                            }
                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    const pct = Math.max(0, Math.min(100, Math.round((mouse.x / subSoundBar.width) * 100)));
                                                    Services.SystemService.setVolumePercent(pct);
                                                }
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
                                                        text: modelData.name.toLowerCase().includes("hdmi") ? "󰡁" : (modelData.name.toLowerCase().includes("headphone") ? "󰋋" : "󰓃")
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
                                            height: 30
                                            radius: 15
                                            color: Services.SystemService.micMuted ? Qt.rgba(0.35, 0.12, 0.15, 0.4) : Services.Aesthetic.sliderTrackBg
                                            border.color: Services.SystemService.micMuted ? Qt.rgba(1, 0.25, 0.3, 0.35) : (subMicMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
                                            border.width: 1
                                            clip: true
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }

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
                                                width: Services.SystemService.micMuted ? 0 : Math.max(0, Math.min(parent.width, parent.width * (Math.min(100, Services.SystemService.micVolume) / 100)))
                                                height: parent.height
                                                radius: 15
                                                color: Services.SystemService.micInUse ? "#ff9f0a" : Services.Aesthetic.sliderFill
                                                clip: true
                                                Behavior on width { NumberAnimation { duration: 50 } }
                                                Behavior on color { ColorAnimation { duration: 140 } }

                                                Text {
                                                    x: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Services.SystemService.micMuted ? "󰍭" : "󰍬"
                                                    color: "#16161a"
                                                    font.pixelSize: 15
                                                    font.family: root.font
                                                }
                                            }

                                            MouseArea {
                                                id: subMicMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: (mouse) => {
                                                    if (mouse.x < 28) {
                                                        Services.SystemService.toggleMicMute();
                                                    } else {
                                                        const pct = Math.max(0, Math.min(100, Math.round((mouse.x / subMicBar.width) * 100)));
                                                        Services.SystemService.setMicVolumePercent(pct);
                                                    }
                                                }
                                                onPositionChanged: (mouse) => {
                                                    if (pressed) {
                                                        const pct = Math.max(0, Math.min(100, Math.round((mouse.x / subMicBar.width) * 100)));
                                                        Services.SystemService.setMicVolumePercent(pct);
                                                    }
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
                            color: backMM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
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
                        radius: 24
                        clip: true
                        color: Qt.rgba(0.06, 0.06, 0.09, 0.98)
                        border.color: root.playerAccent ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.16)
                        border.width: 1

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
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                // Centered Header Capsule Pill
                                Rectangle {
                                    id: ccHeaderPill
                                    implicitWidth: ccHeaderPillRow.implicitWidth + 24
                                    implicitHeight: 26
                                    radius: 13
                                    color: ccPillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
                                    border.color: ccPillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
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
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                }
                            }

                            // Middle: Big Album Art + Title & Artist
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14

                                // Album Art
                                Rectangle {
                                    width: 52
                                    height: 52
                                    radius: 12
                                    clip: true
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    border.width: 1

                                    Image {
                                        id: ccExpandedArt
                                        anchors.fill: parent
                                        source: root.activePlayer?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: status === Image.Ready && source != ""
                                        asynchronous: true
                                        cache: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰝚"
                                        color: root.playerAccent
                                        font.pixelSize: 24
                                        font.family: root.font
                                        visible: !ccExpandedArt.visible
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
                                        color: Qt.rgba(1, 1, 1, 0.16)
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
                                    color: ccPrevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        color: ccPrevMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
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
                                    color: ccNextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        color: ccNextMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
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
                        implicitHeight: 60
                        radius: 16
                        color: Services.Aesthetic.innerCardBg
                        border.color: Services.Aesthetic.innerCardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

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
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            // Interactive Volume Slider Bar
                            Rectangle {
                                id: ccMediaVolBar
                                Layout.fillWidth: true
                                height: 26
                                radius: 13
                                color: Qt.rgba(1, 1, 1, 0.10)
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: parent.radius
                                    color: Services.SystemService.volumeMuted ? root.theme.accentRed : root.playerAccent
                                    width: Services.SystemService.volumeMuted ? 0 : Math.max(26, Math.min(parent.width, parent.width * (Services.SystemService.volume / 100)))

                                    Behavior on width {
                                        enabled: !ccVolMouse.pressed
                                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                                    }
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Services.SystemService.volumeMuted ? "󰖁" : (Services.SystemService.volume > 50 ? "󰕾" : "󰖀")
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: ccVolMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    function updateVol(mouseX) {
                                        const pct = Math.max(0, Math.min(100, Math.round((mouseX / width) * 100)));
                                        Services.SystemService.setVolumePercent(pct);
                                    }

                                    onPressed: (mouse) => updateVol(mouse.x)
                                    onPositionChanged: (mouse) => {
                                        if (pressed) updateVol(mouse.x);
                                    }
                                    onWheel: (wheel) => {
                                        wheel.accepted = true;
                                        const delta = wheel.angleDelta.y > 0 ? 5 : -5;
                                        Services.SystemService.setVolumePercent(Math.max(0, Math.min(100, Services.SystemService.volume + delta)));
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
                                return isCurrent ? Qt.rgba(1, 1, 1, 0.08) : Services.Aesthetic.innerCardBg;
                            }
                            border.color: root.activePlayer?.identity === modelData.identity ? root.playerAccent : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1

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
