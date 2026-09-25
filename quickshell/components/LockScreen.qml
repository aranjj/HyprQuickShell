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

    // ── Dynamic User Identity ─────────────────────────
    readonly property string currentUser: Quickshell.env("USER") || "unknown"
    readonly property string homeDir: Quickshell.env("HOME") || ("/home/" + currentUser)
    property string displayName: currentUser.charAt(0).toUpperCase() + currentUser.slice(1)

    Process {
        id: gecosProc
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name.length > 0) root.displayName = name;
            }
        }
    }

    property bool authenticating: false
    property bool authError: false
    property string errorMessage: ""
    property int shakeOffset: 0
    property bool caffeineActive: Services.SystemService.caffeineActive
    property bool idleAutoLockEnabled: true
    property int playerTick: 0

    // ── Active MPRIS player (intelligently scored & prioritized) ─
    property var activePlayer: {
        root.playerTick;
        const players = Mpris.players.values;
        if (!players || players.length === 0) return null;

        let bestPlayer = null;
        let bestScore = -99999;

        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p) continue;

            let score = 0;

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

    Timer {
        interval: 1000
        running: sessionLock.locked
        repeat: true
        onTriggered: root.playerTick++
    }

    // ── Transition and Audio Feedback State ─────────────
    property bool unlocking: false

    Timer {
        id: unlockFinishTimer
        interval: 130
        repeat: false
        onTriggered: {
            root.unlocking = false;
            sessionLock.locked = false;
        }
    }

    Process {
        id: soundProc
        command: ["sh", "-c", ""]
    }

   function playLockSound() {
        soundProc.running = false;
        soundProc.command = ["sh", "-c", "pw-play " + root.homeDir + "/.config/quickshell/sounds/lock.wav 2>/dev/null || paplay " + root.homeDir + "/.config/quickshell/sounds/lock.wav 2>/dev/null || canberra-gtk-play -i service-logout 2>/dev/null &"];
        soundProc.running = true;
    }

    function playUnlockSound() {
        soundProc.running = false;
        soundProc.command = ["sh", "-c", "pw-play " + root.homeDir + "/.config/quickshell/sounds/unlock.wav 2>/dev/null || paplay " + root.homeDir + "/.config/quickshell/sounds/unlock.wav 2>/dev/null || canberra-gtk-play -i service-login 2>/dev/null &"];
        soundProc.running = true;
    }

    function triggerUnlock() {
        if (root.unlocking) return;
        root.unlocking = true;
        root.authError = false;
        root.errorMessage = "";
        playUnlockSound();
        unlockFinishTimer.restart();
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
            root.triggerUnlock();
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
        root.unlocking = false;
        playLockSound();
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
        enabled: !Services.SystemService.idleInhibited

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
        enabled: root.idleAutoLockEnabled && !Services.SystemService.idleInhibited

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
        enabled: !sessionLock.locked && !Services.SystemService.idleInhibited

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
        enabled: !Services.SystemService.idleInhibited

        onIsIdleChanged: {
            if (isIdle) {
                Services.SystemService.runCmd("systemctl suspend");
            }
        }
    }

    Connections {
        target: Services.SystemService
        function onIdleInhibitedChanged() {
            if (Services.SystemService.idleInhibited && !sessionLock.locked) {
                Services.OsdService.suppressBrightness = true;
                unsuppressBrightnessTimer.restart();
                Services.SystemService.runCmd("brightnessctl -r >/dev/null 2>&1");
                Services.SystemService.isIdleOrLocked = false;
            }
        }
    }

    // ── PAM Authentication Context ──────────────────────────────
    PamContext {
        id: pam
        user: root.currentUser
        config: "system-auth"

        onCompleted: (result) => {
            root.authenticating = false;
            if (result === PamResult.Success || result === 0) {
                root.triggerUnlock();
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
        if (!pwd || root.authenticating || root.unlocking) return;
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
                color: "#000000"

                Rectangle {
                    id: surfaceRoot
                    anchors.fill: parent
                    color: Services.Aesthetic.preset === "oled" ? "#000000"
                         : (Services.Aesthetic.preset === "solid" ? Services.ThemeService.colSurface : "#000000")
                    focus: true

                    property bool surfaceRevealed: false
                    Component.onCompleted: {
                        surfaceRevealed = true;
                    }

                    Behavior on color { ColorAnimation { duration: 250 } }

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

                    // ── Wallpaper Background with Aesthetic Blur ───
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
                        blur: Services.Aesthetic.preset === "crystal" ? 0.50 : 0.95
                        blurMax: 64
                        brightness: Services.Aesthetic.preset === "crystal" ? -0.10 : -0.22
                        saturation: Services.Aesthetic.preset === "crystal" ? 0.05 : -0.15
                        visible: Services.Aesthetic.preset !== "oled" && Services.Aesthetic.preset !== "solid"

                        opacity: surfaceRoot.surfaceRevealed ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    // Aesthetic Themed Dark Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: {
                            switch (Services.Aesthetic.preset) {
                                case "oled": return "#000000";
                                case "solid": return Services.ThemeService.colSurface;
                                case "crystal": return Qt.rgba(0.04, 0.04, 0.08, 0.25);
                                case "frosted":
                                default: return Qt.rgba(0.08, 0.09, 0.14, 0.45);
                            }
                        }
                        Behavior on color { ColorAnimation { duration: 250 } }

                        opacity: surfaceRoot.surfaceRevealed ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    // Click anywhere to focus password
                    MouseArea {
                        anchors.fill: parent
                        onClicked: passField.forceActiveFocus()
                    }

                    // ── Smooth Interactive Content Container ──────────
                    Item {
                        id: contentContainer
                        anchors.fill: parent
                        opacity: (!surfaceRoot.surfaceRevealed || root.unlocking) ? 0.0 : 1.0
                        scale: root.unlocking ? 1.02 : (surfaceRoot.surfaceRevealed ? 1.0 : 1.02)
                        y: root.unlocking ? -8 : (surfaceRoot.surfaceRevealed ? 0 : 10)
                        transformOrigin: Item.Center

                        Behavior on opacity {
                            NumberAnimation {
                                duration: root.unlocking ? 120 : 250
                                easing.type: root.unlocking ? Easing.InQuad : Easing.OutCubic
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: root.unlocking ? 140 : 280
                                easing.type: root.unlocking ? Easing.OutQuad : Easing.OutCubic
                            }
                        }
                        Behavior on y {
                            NumberAnimation {
                                duration: root.unlocking ? 120 : 250
                                easing.type: root.unlocking ? Easing.InQuad : Easing.OutCubic
                            }
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
                                    text: Services.SystemService.wifiBarIcon
                                    color: (Services.SystemService.networkType === "disconnected" && !Services.SystemService.wifiConnected) ? Qt.rgba(1, 1, 1, 0.4) : "#ffffff"
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
                            id: avatarContainer
                            width: 96
                            height: 96
                            radius: width / 2
                            color: Services.Aesthetic.preset === "oled" ? Qt.rgba(1, 1, 1, 0.05)
                                 : (Services.Aesthetic.preset === "solid" ? Services.Aesthetic.innerCardBg : Qt.rgba(1, 1, 1, 0.14))
                            border.color: Services.Aesthetic.preset === "oled" ? Qt.rgba(1, 1, 1, 0.12)
                                        : (Services.Aesthetic.preset === "solid" ? Services.Aesthetic.innerCardBorder : Qt.rgba(1, 1, 1, 0.20))
                            border.width: 1
                            Layout.alignment: Qt.AlignHCenter

                            Behavior on color { ColorAnimation { duration: 250 } }
                            Behavior on border.color { ColorAnimation { duration: 250 } }

                            Image {
                                id: userAvatarImg
                                anchors.fill: parent
                                source: "file:///var/lib/AccountsService/icons/" + root.currentUser
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                                asynchronous: true
                                cache: true
                            }

                            Rectangle {
                                id: userAvatarMask
                                anchors.fill: parent
                                radius: width / 2
                                color: "#ffffff"
                                antialiasing: true
                                visible: false
                                layer.enabled: true
                            }

                            MultiEffect {
                                id: userAvatarEffect
                                anchors.fill: parent
                                source: userAvatarImg
                                maskEnabled: true
                                maskSource: userAvatarMask
                                visible: userAvatarImg.status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.color: avatarContainer.border.color
                                border.width: avatarContainer.border.width
                                antialiasing: true
                                z: 2
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
                            text: root.displayName
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }

                        // Password Input Pill
                        Rectangle {
                            width: 300
                            height: 46
                            radius: 23
                            color: {
                                switch (Services.Aesthetic.preset) {
                                    case "oled": return Qt.rgba(1, 1, 1, 0.06);
                                    case "solid": return Services.ThemeService.colSurfaceContainer;
                                    case "crystal": return Qt.rgba(1, 1, 1, 0.10);
                                    case "frosted":
                                    default: return Qt.rgba(1, 1, 1, 0.12);
                                }
                            }
                            border.color: root.authError ? "#e01b24"
                                        : (passField.activeFocus ? root.theme.accent
                                        : (Services.Aesthetic.preset === "oled" ? Qt.rgba(1, 1, 1, 0.14)
                                        : (Services.Aesthetic.preset === "solid" ? Services.Aesthetic.cardBorder
                                        : Qt.rgba(1, 1, 1, 0.16))))
                            border.width: root.authError ? 2 : 1
                            Layout.alignment: Qt.AlignHCenter

                            Behavior on color { ColorAnimation { duration: 200 } }
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

                                // Arrow Submit Button
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: submitMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25)
                                         : (passField.text.length > 0 ? root.theme.accent
                                         : (Services.Aesthetic.preset === "oled" ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.10)))
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
                        color: {
                            switch (Services.Aesthetic.preset) {
                                case "oled": return "#000000";
                                case "solid": return Services.ThemeService.colSurfaceContainer;
                                case "crystal": return Qt.rgba(0.04, 0.04, 0.08, 0.50);
                                case "frosted":
                                default: return Qt.rgba(0.10, 0.11, 0.16, 0.85);
                            }
                        }
                        border.color: {
                            switch (Services.Aesthetic.preset) {
                                case "oled": return Qt.rgba(1, 1, 1, 0.14);
                                case "solid": return Services.Aesthetic.cardBorder;
                                case "crystal": return Qt.rgba(1, 1, 1, 0.22);
                                case "frosted":
                                default: return Qt.rgba(1, 1, 1, 0.14);
                            }
                        }
                        border.width: Services.Aesthetic.borderWidth
                        visible: Boolean(root.activePlayer && (root.activePlayer.trackTitle || root.isMediaPlaying))

                        Behavior on color { ColorAnimation { duration: 250 } }
                        Behavior on border.color { ColorAnimation { duration: 250 } }

                        RowLayout {
                            id: mediaContentRow
                            anchors.centerIn: parent
                            spacing: 12

                            // Album Artwork or Music Icon Thumbnail (slightly rounded 36x36, radius 8)
                            Rectangle {
                                id: lockTrackBox
                                width: 36
                                height: 36
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Image {
                                    id: lockTrackThumb
                                    anchors.fill: parent
                                    source: root.displayTrackArt
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                    asynchronous: true
                                    cache: true
                                }

                                Rectangle {
                                    id: lockTrackMask
                                    anchors.fill: parent
                                    radius: 8
                                    color: "#ffffff"
                                    antialiasing: true
                                    visible: false
                                    layer.enabled: true
                                }

                                MultiEffect {
                                    id: lockTrackEffect
                                    anchors.fill: parent
                                    source: lockTrackThumb
                                    maskEnabled: true
                                    maskSource: lockTrackMask
                                    visible: lockTrackThumb.status === Image.Ready && root.displayTrackArt !== ""
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: "transparent"
                                    border.color: lockTrackBox.border.color
                                    border.width: lockTrackBox.border.width
                                    antialiasing: true
                                    z: 2
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰎆"
                                    color: root.theme.accent
                                    font.pixelSize: 18
                                    font.family: root.font
                                    visible: !lockTrackEffect.visible
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
                                    color: playM.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                                               : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.20)
                                    border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40)
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 150 } }

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
}
