import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import "../bar" as Bar
import "../services" as Services

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    property bool authenticating: false
    property bool authError: false
    property string errorMessage: ""
    property int shakeOffset: 0
    property bool caffeineActive: Services.SystemService.caffeineActive
    property bool idleAutoLockEnabled: true
    property int playerTick: 0

    // ── Active MPRIS player ──────────────────────────────
    property var activePlayer: {
        root.playerTick;
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
        return players[0] || null;
    }

    readonly property bool isMediaPlaying: root.activePlayer?.playbackState === MprisPlaybackState.Playing

    Timer {
        interval: 1000
        running: sessionLock.locked
        repeat: true
        onTriggered: root.playerTick++
    }

    // ── IPC Handler for External / Hyprland Lock Trigger ────────
    IpcHandler {
        target: "lock"

        function lock(): void {
            root.startLock();
        }

        function unlock(): void {
            root.authenticating = false;
            root.authError = false;
            sessionLock.locked = false;
        }

        function isLocked(): bool {
            return sessionLock.locked;
        }

        function toggleCaffeine(): void {
            Services.SystemService.toggleCaffeine();
        }

        function toggleAutoLock(): void {
            root.idleAutoLockEnabled = !root.idleAutoLockEnabled;
        }
    }

    function startLock() {
        if (sessionLock.locked) return;
        Services.SystemService.closeAllPopups();
        root.authError = false;
        root.errorMessage = "";
        root.authenticating = false;
        root.pendingPassword = "";
        sessionLock.locked = true;
    }

    // ── Brightness OSD Suppression Timer ────────────────────────
    Timer {
        id: unsuppressBrightnessTimer
        interval: 1500
        repeat: false
        onTriggered: Services.OsdService.suppressBrightness = false
    }

    // ── 1. Idle Dimming Monitor (3 min on AC, 2 min on Battery) ───
    IdleMonitor {
        id: dimMonitor
        timeout: Services.SystemService.batteryPlugged ? 180 : 120
        respectInhibitors: true
        enabled: !Services.SystemService.caffeineActive

        onIsIdleChanged: {
            Services.OsdService.suppressBrightness = true;
            unsuppressBrightnessTimer.restart();
            if (isIdle && !sessionLock.locked) {
                Services.SystemService.runCmd("brightnessctl -s set 20% >/dev/null 2>&1");
            } else if (!isIdle && !sessionLock.locked) {
                Services.SystemService.runCmd("brightnessctl -r >/dev/null 2>&1");
            }
            Services.SystemService.isIdleOrLocked = (sessionLock.locked || isIdle);
        }
    }

    // ── 2. Auto-Lock Monitor (5 minutes) ─────────────────────────
    IdleMonitor {
        id: lockMonitor
        timeout: 300
        respectInhibitors: true
        enabled: root.idleAutoLockEnabled && !Services.SystemService.caffeineActive

        onIsIdleChanged: {
            if (isIdle && !sessionLock.locked) {
                root.startLock();
            }
        }
    }

    // ── 3. Lock Screen DPMS Monitor (Display sleep after 45s on lock)
    IdleMonitor {
        id: lockDpmsMonitor
        timeout: 45
        enabled: sessionLock.locked && !Services.SystemService.caffeineActive

        onIsIdleChanged: {
            if (isIdle && sessionLock.locked) {
                Services.SystemService.runCmd("hyprctl dispatch dpms off");
            } else if (!isIdle) {
                Services.SystemService.runCmd("hyprctl dispatch dpms on");
            }
        }
    }

    // ── 4. Session DPMS Monitor (12 min on AC, 8 min on Battery) ──
    IdleMonitor {
        id: sessionDpmsMonitor
        timeout: Services.SystemService.batteryPlugged ? 720 : 480
        respectInhibitors: true
        enabled: !sessionLock.locked && !Services.SystemService.caffeineActive

        onIsIdleChanged: {
            if (isIdle) {
                Services.SystemService.runCmd("hyprctl dispatch dpms off");
            } else {
                Services.SystemService.runCmd("hyprctl dispatch dpms on");
            }
        }
    }

    // ── 5. Auto-Suspend to RAM (35 min on AC, 20 min on Battery) ──
    IdleMonitor {
        id: suspendMonitor
        timeout: Services.SystemService.batteryPlugged ? 2100 : 1200
        respectInhibitors: true
        enabled: !Services.SystemService.caffeineActive

        onIsIdleChanged: {
            if (isIdle) {
                Services.SystemService.runCmd("systemctl suspend");
            }
        }
    }

    // ── PAM Authentication Context ──────────────────────────────
    PamContext {
        id: pam
        user: "aran"
        config: "system-auth"

        onCompleted: (result) => {
            root.authenticating = false;
            if (result === PamResult.Success || result === 0) {
                root.authError = false;
                root.errorMessage = "";
                sessionLock.locked = false;
            } else {
                root.authError = true;
                root.errorMessage = "Sorry, that didn't work. Please try again.";
                shakeAnim.start();
                pam.start();
            }
        }

        onError: (err) => {
            root.authenticating = false;
            root.authError = true;
            root.errorMessage = "Authentication error";
            shakeAnim.start();
            pam.start();
        }
    }

    property string pendingPassword: ""

    function submitPassword(pwd) {
        if (!pwd || root.authenticating) return;
        root.authenticating = true;
        root.authError = false;
        root.errorMessage = "";

        if (pam.responseRequired) {
            pam.respond(pwd);
        } else {
            root.pendingPassword = pwd;
            if (!pam.active) {
                pam.start();
            }
        }
    }

    Connections {
        target: pam
        function onResponseRequiredChanged() {
            if (pam.responseRequired && root.pendingPassword) {
                const p = root.pendingPassword;
                root.pendingPassword = "";
                pam.respond(p);
            }
        }
    }

    // ── GNOME Shake Animation on Failed Authentication ──────────
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeOffset"; from: 0; to: -18; duration: 45; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; from: -18; to: 18; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; from: 18; to: -12; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; from: -12; to: 12; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; from: 12; to: 0; duration: 45; easing.type: Easing.OutQuad }
    }

    // ── Wayland Session Lock ─────────────────────────────────────
    WlSessionLock {
        id: sessionLock
        locked: false

        onLockStateChanged: {
            Services.SystemService.isIdleOrLocked = (locked || dimMonitor.isIdle);
            if (locked) {
                root.authError = false;
                root.errorMessage = "";
                root.authenticating = false;
                root.pendingPassword = "";
                if (!pam.active) {
                    pam.start();
                }
            } else {
                Services.SystemService.runCmd("hyprctl dispatch dpms on");
            }
        }

        surface: Component {
            WlSessionLockSurface {
                id: lockSurface

                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    focus: true

                    // Global Focus Router
                    Keys.onPressed: (event) => {
                        if (!passField.activeFocus) {
                            passField.forceActiveFocus();
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (passField.text.length > 0) {
                                    const p = passField.text;
                                    passField.text = "";
                                    root.submitPassword(p);
                                }
                            } else if (event.text.length > 0 && event.key !== Qt.Key_Escape) {
                                passField.text += event.text;
                            }
                        }
                    }

                    // ── Wallpaper Background with GNOME Blur ───────
                    Image {
                        id: bgWallpaper
                        anchors.fill: parent
                        source: Services.WallpaperService.currentWallpaper
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: bgWallpaper
                        blurEnabled: true
                        blur: 0.95
                        blurMax: 64
                        brightness: -0.22
                        saturation: 1.10
                    }

                    // GNOME Frosted Dark Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(0.08, 0.09, 0.14, 0.45)
                    }

                    // Click anywhere to focus password
                    MouseArea {
                        anchors.fill: parent
                        onClicked: passField.forceActiveFocus()
                    }

                    // ── GNOME Top Bar ────────────────────────────────
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 36
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20

                            Item { Layout.fillWidth: true }

                            // GNOME System Status Indicators
                            RowLayout {
                                spacing: 14

                                // Caffeine Indicator
                                RowLayout {
                                    spacing: 5
                                    visible: root.caffeineActive

                                    Text {
                                        text: "󰅶"
                                        color: "#f59e0b"
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }
                                }

                                // Network
                                Text {
                                    text: Services.SystemService.networkType === "ethernet" ? "󰈀"
                                        : Services.SystemService.networkType === "wifi" ? "󰖩" : "󰖪"
                                    color: Services.SystemService.networkType === "disconnected" ? Qt.rgba(1, 1, 1, 0.4) : "#ffffff"
                                    font.pixelSize: 15
                                    font.family: root.font
                                }

                                // Battery
                                RowLayout {
                                    spacing: 5
                                    Text {
                                        text: Services.SystemService.batteryIcon
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                        font.family: root.font
                                    }
                                    Text {
                                        text: Services.SystemService.batteryLevel + "%"
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }

                    // ── GNOME Clock & Date (Upper Third) ─────────────
                    ColumnLayout {
                        id: clockCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: parent.height * 0.16
                        spacing: 6

                        Text {
                            text: Services.ClockService.time
                            color: "#ffffff"
                            font.pixelSize: 96
                            font.weight: Font.DemiBold
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: Services.ClockService.fullDate
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.pixelSize: 22
                            font.weight: Font.Normal
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ── GNOME Login / Authentication Box (Center) ────
                    ColumnLayout {
                        id: authCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: root.shakeOffset
                        anchors.top: parent.top
                        anchors.topMargin: parent.height * 0.46
                        spacing: 14

                        // User Avatar
                        Rectangle {
                            width: 96
                            height: 96
                            radius: 48
                            color: Qt.rgba(1, 1, 1, 0.14)
                            border.color: Qt.rgba(1, 1, 1, 0.20)
                            border.width: 1
                            Layout.alignment: Qt.AlignHCenter
                            clip: true

                            Image {
                                id: userAvatarImg
                                anchors.fill: parent
                                source: "file:///var/lib/AccountsService/icons/aran"
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰀉"
                                color: "#ffffff"
                                font.pixelSize: 48
                                font.family: root.font
                                visible: userAvatarImg.status !== Image.Ready
                            }
                        }

                        // Username
                        Text {
                            text: "Aran"
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }

                        // GNOME Password Input Pill
                        Rectangle {
                            width: 300
                            height: 46
                            radius: 23
                            color: Qt.rgba(1, 1, 1, 0.12)
                            border.color: root.authError ? "#e01b24" : (passField.activeFocus ? "#3584e4" : Qt.rgba(1, 1, 1, 0.16))
                            border.width: root.authError ? 2 : 1
                            Layout.alignment: Qt.AlignHCenter

                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 6
                                spacing: 10

                                TextInput {
                                    id: passField
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    color: "#ffffff"
                                    font.pixelSize: 15
                                    font.family: root.font
                                    echoMode: TextInput.Password
                                    focus: true

                                    Text {
                                        anchors.fill: parent
                                        text: "Password"
                                        color: Qt.rgba(1, 1, 1, 0.45)
                                        font: parent.font
                                        visible: !parent.text && !parent.activeFocus
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Keys.onReturnPressed: {
                                        if (text.length > 0) {
                                            const p = text;
                                            text = "";
                                            root.submitPassword(p);
                                        }
                                    }

                                    Keys.onEscapePressed: {
                                        text = "";
                                    }

                                    Component.onCompleted: {
                                        forceActiveFocus();
                                    }
                                }

                                // GNOME Arrow Submit Button
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: submitMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : (passField.text.length > 0 ? "#3584e4" : Qt.rgba(1, 1, 1, 0.10))
                                    Layout.alignment: Qt.AlignVCenter

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        id: submitIconText
                                        anchors.centerIn: parent
                                        text: root.authenticating ? "󰑮" : "󰄾"
                                        color: "#ffffff"
                                        font.pixelSize: 15
                                        font.family: root.font

                                        RotationAnimation on rotation {
                                            running: root.authenticating
                                            from: 0
                                            to: 360
                                            duration: 900
                                            loops: Animation.Infinite
                                        }
                                    }

                                    MouseArea {
                                        id: submitMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (passField.text.length > 0) {
                                                const p = passField.text;
                                                passField.text = "";
                                                root.submitPassword(p);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // GNOME Error Message
                        Text {
                            text: root.errorMessage
                            color: "#ff7b63"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            font.family: root.font
                            visible: root.authError
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ── Bottom Media Pill (if music playing) ─────────
                    Rectangle {
                        id: mediaPill
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 36
                        height: 52
                        implicitWidth: mediaContentRow.implicitWidth + 30
                        radius: 26
                        color: Qt.rgba(0.10, 0.11, 0.16, 0.85)
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1
                        visible: Boolean(root.activePlayer && (root.activePlayer.trackTitle || root.isMediaPlaying))

                        RowLayout {
                            id: mediaContentRow
                            anchors.centerIn: parent
                            spacing: 12

                            // Album Artwork or Music Icon Thumbnail
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 8
                                clip: true
                                color: Qt.rgba(1, 1, 1, 0.10)
                                Layout.alignment: Qt.AlignVCenter

                                Image {
                                    id: lockTrackThumb
                                    anchors.fill: parent
                                    source: root.activePlayer?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: status === Image.Ready && source != ""
                                    asynchronous: true
                                    cache: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰎆"
                                    color: root.theme.accent
                                    font.pixelSize: 18
                                    font.family: root.font
                                    visible: !lockTrackThumb.visible
                                }
                            }

                            // Track Information
                            ColumnLayout {
                                spacing: 2
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    text: root.activePlayer?.trackTitle || "Media"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.weight: Font.SemiBold
                                    font.family: root.font
                                    Layout.maximumWidth: 260
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.activePlayer?.trackArtist || root.activePlayer?.identity || ""
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    font.pixelSize: 11
                                    font.family: root.font
                                    Layout.maximumWidth: 260
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }

                            // Media Controls
                            RowLayout {
                                spacing: 6
                                Layout.alignment: Qt.AlignVCenter

                                // Previous Track
                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: prevM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: prevM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activePlayer?.previous();
                                            passField.forceActiveFocus();
                                        }
                                    }
                                }

                                // Play / Pause Button
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: playM.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                        color: "#ffffff"
                                        font.pixelSize: 15
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: playM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activePlayer?.togglePlaying();
                                            passField.forceActiveFocus();
                                        }
                                    }
                                }

                                // Next Track
                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: nextM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        color: "#ffffff"
                                        font.pixelSize: 14
                                        font.family: root.font
                                    }

                                    MouseArea {
                                        id: nextM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activePlayer?.next();
                                            passField.forceActiveFocus();
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
