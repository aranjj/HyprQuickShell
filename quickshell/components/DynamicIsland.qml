import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
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

    // ── Active MPRIS player (intelligently scored & prioritized) ─
    property var activePlayer: {
        const players = Mpris.players.values;
        if (!players || players.length === 0) return null;

        let bestPlayer = null;
        let bestScore = -99999;

        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p) continue;

            let score = 0;

            // 1. Playback state (primary factor)
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

    readonly property string mediaTrackString: {
        if (!root.activePlayer) return "";
        const a = root.activePlayer.trackArtist ?? "";
        const t = root.activePlayer.trackTitle ?? "";
        if (a && t) return a + " — " + t;
        return t || a || "";
    }

    function formatTime(secs) {
        if (isNaN(secs) || secs <= 0) return "0:00";
        const s = Math.floor(secs);
        const m = Math.floor(s / 60);
        const rem = s % 60;
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

    // ── Player Accent Color ───────────────────────────────
    readonly property color playerAccent: {
        const id = (root.activePlayer?.identity ?? "").toLowerCase();
        if (id.includes("spotify")) return "#1db954";
        return root.theme.accent;
    }

    // ── Live Playback Clock Tick ─────────────────────────
    property int clockTick: 0

    Timer {
        id: playbackClock
        interval: 200
        repeat: true
        running: root.isMediaPlaying && root.islandMode === "mediaExpanded"
        onTriggered: root.clockTick++
    }

    // ── Live Cava Audio Visualizer ───────────────────────
    property real cavaBar0: 0.0
    property real cavaBar1: 0.0
    property real cavaBar2: 0.0
    property real cavaBar3: 0.0

    Process {
        id: cavaProc
        command: ["cava", "-p", "/home/aran/.config/quickshell/cava.conf"]
        running: root.hasMedia && root.isMediaPlaying && !root.isFullscreen
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const parts = data.trim().split(";");
                if (parts.length >= 4) {
                    root.cavaBar0 = Math.max(0, Math.min(1.0, (parseInt(parts[0]) || 0) / 100.0));
                    root.cavaBar1 = Math.max(0, Math.min(1.0, (parseInt(parts[1]) || 0) / 100.0));
                    root.cavaBar2 = Math.max(0, Math.min(1.0, (parseInt(parts[2]) || 0) / 100.0));
                    root.cavaBar3 = Math.max(0, Math.min(1.0, (parseInt(parts[3]) || 0) / 100.0));
                }
            }
        }
    }

    onIsMediaPlayingChanged: {
        if (!isMediaPlaying) {
            cavaBar0 = 0.0;
            cavaBar1 = 0.0;
            cavaBar2 = 0.0;
            cavaBar3 = 0.0;
        }
    }

    // ── Island State Machine ─────────────────────────────
    property bool isMediaExpanded: false
    property bool isUserScrubbing: false
    readonly property bool hasNotification: Services.NotificationService.islandNotification !== null
    readonly property bool hasOsd: Services.OsdService.visible
    readonly property bool hasMedia: activePlayer !== null && mediaTrackString.length > 0

    function resetInactivityTimer() {
        if (autoCollapseTimer.running) {
            autoCollapseTimer.restart();
        }
    }

    Timer {
        id: autoCollapseTimer
        interval: 3000
        repeat: false
        running: root.islandMode === "mediaExpanded" && !root.isUserScrubbing
        onTriggered: {
            console.log("[DynamicIsland] 3s inactivity timeout, collapsing island");
            root.isMediaExpanded = false;
        }
    }

    onIsMediaExpandedChanged: {
        if (isMediaExpanded) {
            root.resetInactivityTimer();
        } else {
            root.isUserScrubbing = false;
        }
    }

    IpcHandler {
        target: "island"
        function toggle() {
            if (root.hasMedia) root.isMediaExpanded = !root.isMediaExpanded;
        }
        function expand() {
            if (root.hasMedia) root.isMediaExpanded = true;
        }
        function collapse() {
            root.isMediaExpanded = false;
        }
    }

    // ── Fullscreen Window Tracking ───────────────────────
    property bool isFullscreen: false

    Process {
        id: fsProc
        command: ["sh", "-c", "hyprctl activeworkspace -j | grep -q '\"hasfullscreen\": true' && echo 1 || echo 0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.isFullscreen = (text.trim() === "1");
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            if (!fsProc.running) fsProc.running = true;
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "fullscreen") {
                root.isFullscreen = (event.data !== "0");
                if (!fsProc.running) fsProc.running = true;
            } else if (event.name === "workspace" || event.name === "activewindow" || event.name === "focusedmon") {
                if (!fsProc.running) fsProc.running = true;
            }
        }

        function onFocusedWorkspaceChanged() {
            if (Hyprland.focusedWorkspace) {
                root.isFullscreen = Hyprland.focusedWorkspace.hasFullscreen;
            }
            if (!fsProc.running) fsProc.running = true;
        }

        function onActiveToplevelChanged() {
            if (!fsProc.running) fsProc.running = true;
        }
    }

    onIsFullscreenChanged: {
        if (isFullscreen) {
            root.isMediaExpanded = false;
        }
    }

    // ── Priority State Machine ───────────────────────────
    // Priority: Hardware OSD > Notification Alert > Media Expanded > Media Compact > Hidden
    // When playing a fullscreen video or in fullscreen mode, media player is hidden to avoid obstruction.
    readonly property string islandMode: {
        if (hasOsd) return "osd";
        if (hasNotification) return "notification";
        if (!isFullscreen) {
            if (hasMedia && isMediaExpanded) return "mediaExpanded";
            if (hasMedia) return "mediaCompact";
        }
        return "hidden";
    }

    // ── Satellite (Dual-Pill) State Engine ───────────────
    readonly property bool satelliteActive: {
        if (isFullscreen) return false;
        if (islandMode === "osd") return hasMedia || hasNotification;
        if (islandMode === "notification") return hasMedia;
        return false;
    }

    readonly property string satelliteType: {
        if (isFullscreen) return "none";
        if (islandMode === "osd") {
            if (hasMedia) return "media";
            if (hasNotification) return "notification";
        }
        if (islandMode === "notification") {
            if (hasMedia) return "media";
        }
        return "none";
    }

    onIslandModeChanged: console.log("[DynamicIsland] islandMode changed to:", islandMode, "satelliteActive:", satelliteActive, "satelliteType:", satelliteType)

    Variants {
        model: Quickshell.screens

        // Invisible click-outside dismiss backdrop when expanded
        PanelWindow {
            id: dismissBackdrop
            required property ShellScreen modelData
            screen: modelData

            visible: root.isMediaExpanded && !root.isFullscreen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-island-backdrop"
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("[DynamicIsland] Clicked outside dynamic island, collapsing");
                    root.isMediaExpanded = false;
                }
                onWheel: (wheel) => {
                    wheel.accepted = true;
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: islandWin
            required property ShellScreen modelData
            screen: modelData

            readonly property bool screenFullscreen: {
                try {
                    const mon = Hyprland.monitorFor(modelData);
                    if (mon?.activeWorkspace) return mon.activeWorkspace.hasFullscreen;
                } catch(e) {}
                return root.isFullscreen;
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-dynamic-island"
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
            }

            margins {
                top: 4
            }

            color: "transparent"
            visible: root.islandMode !== "hidden" && (!screenFullscreen || root.islandMode === "osd")

            implicitWidth: 540
            implicitHeight: 240

            mask: Region {
                Region { item: islandContainer }
                Region { item: satellitePill }
            }

            BackgroundEffect.blurRegion: Region {
                Region { item: islandContainer }
                Region { item: satellitePill }
            }

            // ── Main Morphing Island Pill ─────────────────
            Rectangle {
                id: islandContainer
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                clip: true

                    // Base card mouse handler (resets inactivity timer on hover/clicks)
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: root.resetInactivityTimer()
                        onClicked: root.resetInactivityTimer()
                        onWheel: (wheel) => {
                            wheel.accepted = true;
                            root.resetInactivityTimer();
                        }
                    }

                    width: {
                        if (root.islandMode === "notification") return 410;
                        if (root.islandMode === "mediaExpanded") return 410;
                        if (root.islandMode === "osd") return 340;
                        if (root.islandMode === "mediaCompact") return Math.max(200, Math.min(350, compactContent.implicitWidth + 24));
                        return 0;
                    }

                    height: {
                        if (root.islandMode === "notification") return 74;
                        if (root.islandMode === "mediaExpanded") return 190;
                        if (root.islandMode === "osd") return 50;
                        if (root.islandMode === "mediaCompact") return 28;
                        return 0;
                    }

                    radius: {
                        if (root.islandMode === "notification") return 24;
                        if (root.islandMode === "mediaExpanded") return 24;
                        if (root.islandMode === "osd") return 22;
                        if (root.islandMode === "mediaCompact") return 14;
                        return 0;
                    }

                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 250 } }

                // Organic Spring Physics (Apple-grade micro-spring)
                Behavior on width {
                    NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.04 }
                }
                Behavior on height {
                    NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.04 }
                }
                Behavior on radius {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }


                // ═══════════════════════════════════════════
                // VIEW 1: COMPACT MEDIA PILL (True macOS Bar Island)
                // ═══════════════════════════════════════════
                Item {
                    id: compactView
                    anchors.fill: parent
                    visible: root.islandMode === "mediaCompact" || opacity > 0.0
                    opacity: root.islandMode === "mediaCompact" ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Entire compact pill expands into full media modal on click
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.isMediaExpanded = true
                    }

                    Row {
                        id: compactContent
                        anchors.centerIn: parent
                        spacing: 8

                        // Thumbnail (slightly rounded 18x18)
                        Rectangle {
                            id: compactArtBox
                            width: 18
                            height: 18
                            radius: 4.5
                            color: Qt.rgba(0.12, 0.12, 0.15, 0.8)
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: compactArt
                                anchors.fill: parent
                                source: root.displayTrackArt
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                                asynchronous: true
                                cache: true
                            }

                            Rectangle {
                                id: compactArtMask
                                anchors.fill: parent
                                radius: 4.5
                                color: "#ffffff"
                                antialiasing: true
                                visible: false
                                layer.enabled: true
                            }

                            MultiEffect {
                                id: compactArtEffect
                                anchors.fill: parent
                                source: compactArt
                                maskEnabled: true
                                maskSource: compactArtMask
                                visible: compactArt.status === Image.Ready && root.displayTrackArt !== ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰝚"
                                color: root.playerAccent
                                font.pixelSize: 11
                                font.family: root.font
                                visible: !compactArtEffect.visible
                            }
                        }

                        // Scrolling song text
                        Item {
                            id: compactTextViewport
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true

                            readonly property int maxVisibleWidth: 155
                            readonly property bool shouldScroll: compactMeasureText.implicitWidth > maxVisibleWidth
                            width: shouldScroll ? maxVisibleWidth : Math.max(compactMeasureText.implicitWidth, 20)

                            Text {
                                id: compactMeasureText
                                text: root.mediaTrackString
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: Font.DemiBold
                                visible: false
                            }

                            Item {
                                id: compactMarqueeContent
                                height: parent.height
                                width: compactMarqueeRow.implicitWidth
                                x: 0

                                Row {
                                    id: compactMarqueeRow
                                    spacing: 30
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: compactSong1
                                        text: root.mediaTrackString
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        id: compactSong2
                                        text: root.mediaTrackString
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: Font.DemiBold
                                        visible: compactTextViewport.shouldScroll
                                    }
                                }

                                NumberAnimation {
                                    id: compactMarqueeAnim
                                    target: compactMarqueeContent
                                    property: "x"
                                    from: 0
                                    to: -(compactSong1.implicitWidth + compactMarqueeRow.spacing)
                                    duration: Math.max(2000, (compactSong1.implicitWidth + compactMarqueeRow.spacing) * 35)
                                    loops: Animation.Infinite
                                }
                            }

                            function updateScroll() {
                                if (!compactTextViewport.shouldScroll) {
                                    compactMarqueeAnim.stop();
                                    compactMarqueeContent.x = 0;
                                    return;
                                }
                                if (root.isMediaPlaying) {
                                    if (compactMarqueeAnim.paused) compactMarqueeAnim.resume();
                                    else if (!compactMarqueeAnim.running) compactMarqueeAnim.start();
                                } else {
                                    if (compactMarqueeAnim.running && !compactMarqueeAnim.paused) {
                                        compactMarqueeAnim.pause();
                                    }
                                }
                            }

                            Component.onCompleted: updateScroll()

                            Connections {
                                target: root
                                function onIsMediaPlayingChanged() {
                                    compactTextViewport.updateScroll();
                                }
                                function onMediaTrackStringChanged() {
                                    compactMarqueeAnim.stop();
                                    compactMarqueeContent.x = 0;
                                    compactTextViewport.updateScroll();
                                }
                            }
                        }

                        // Live Cava Audio Waveform (iOS Dynamic Island Style)
                        Row {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter
                            height: 12

                            Repeater {
                                model: [root.cavaBar0, root.cavaBar1, root.cavaBar2, root.cavaBar3]

                                Rectangle {
                                    required property real modelData
                                    width: 2.5
                                    height: Math.max(2.5, modelData * 12)
                                    radius: 1.25
                                    color: root.isMediaPlaying ? root.playerAccent : Qt.rgba(1, 1, 1, 0.30)
                                    anchors.bottom: parent.bottom

                                    Behavior on height {
                                        NumberAnimation { duration: 60; easing.type: Easing.Linear }
                                    }
                                }
                            }
                        }

                        // Subtle Minimal Play/Pause Button
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: playPauseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: root.isMediaPlaying ? 0 : 0.5
                                text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            MouseArea {
                                id: playPauseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    mouse.accepted = true;
                                    root.activePlayer?.togglePlaying();
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 2: EXPANDED FULL MEDIA PLAYER
                // ═══════════════════════════════════════════
                Item {
                    id: expandedView
                    anchors.fill: parent
                    visible: root.islandMode === "mediaExpanded" || opacity > 0.0
                    opacity: root.islandMode === "mediaExpanded" ? 1.0 : 0.0
                    scale: root.islandMode === "mediaExpanded" ? 1.0 : 0.96
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

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
                                id: headerPill
                                implicitWidth: headerPillRow.implicitWidth + 24
                                implicitHeight: 26
                                radius: 13
                                color: pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
                                border.color: pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    id: headerPillRow
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
                                        color: pillMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: pillMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.resetInactivityTimer();
                                        root.isMediaExpanded = false;
                                    }
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
                                id: expandedArtBox
                                width: 52
                                height: 52
                                radius: 10
                                color: Qt.rgba(0, 0, 0, 0.35)
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                Image {
                                    id: expandedArt
                                    anchors.fill: parent
                                    source: root.displayTrackArt
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                    asynchronous: true
                                    cache: true
                                }

                                Rectangle {
                                    id: expandedArtMask
                                    anchors.fill: parent
                                    radius: 10
                                    color: "#ffffff"
                                    antialiasing: true
                                    visible: false
                                    layer.enabled: true
                                }

                                MultiEffect {
                                    id: expandedArtEffect
                                    anchors.fill: parent
                                    source: expandedArt
                                    maskEnabled: true
                                    maskSource: expandedArtMask
                                    visible: expandedArt.status === Image.Ready && root.displayTrackArt !== ""
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: "transparent"
                                    border.color: expandedArtBox.border.color
                                    border.width: expandedArtBox.border.width
                                    antialiasing: true
                                    z: 2
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰝚"
                                    color: root.playerAccent
                                    font.pixelSize: 24
                                    font.family: root.font
                                    visible: !expandedArtEffect.visible
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
                            id: timelineRow
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
                                text: root.formatTime(timelineRow.displayPos)
                                color: timelineRow.scrubPos >= 0 ? root.playerAccent : root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: timelineRow.scrubPos >= 0 ? Font.Bold : Font.Normal
                            }

                            Item {
                                id: trackBarContainer
                                Layout.fillWidth: true
                                height: 18

                                // Track background bar
                                Rectangle {
                                    id: trackBg
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: scrubArea.containsMouse || scrubArea.pressed ? 6 : 4
                                    radius: height / 2
                                    color: Qt.rgba(1, 1, 1, 0.16)
                                    Behavior on height { NumberAnimation { duration: 100 } }

                                    // Filled progress bar
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        radius: parent.radius
                                        color: scrubArea.pressed ? Qt.darker(root.playerAccent, 1.2) : (scrubArea.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : root.playerAccent)
                                        width: parent.width * timelineRow.progressRatio

                                        Behavior on width {
                                            enabled: !scrubArea.pressed
                                            NumberAnimation { duration: 200; easing.type: Easing.Linear }
                                        }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    // Circular scrubber thumb handle
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * timelineRow.progressRatio) - (width / 2)))
                                        width: scrubArea.containsMouse || scrubArea.pressed ? 12 : 0
                                        height: width
                                        radius: width / 2
                                        color: "#ffffff"
                                        border.color: root.playerAccent
                                        border.width: 2
                                        visible: width > 0

                                        Behavior on x {
                                            enabled: !scrubArea.pressed
                                            NumberAnimation { duration: 200; easing.type: Easing.Linear }
                                        }
                                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    }
                                }

                                MouseArea {
                                    id: scrubArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    function updateFromMouse(mouseX) {
                                        const ratio = Math.max(0, Math.min(1.0, mouseX / width));
                                        timelineRow.scrubPos = ratio * timelineRow.totalLen;
                                    }

                                    onPressed: (mouse) => {
                                        root.isUserScrubbing = true;
                                        root.resetInactivityTimer();
                                        updateFromMouse(mouse.x);
                                    }

                                    onPositionChanged: (mouse) => {
                                        root.resetInactivityTimer();
                                        if (pressed) {
                                            updateFromMouse(mouse.x);
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        root.isUserScrubbing = false;
                                        root.resetInactivityTimer();
                                        if (timelineRow.scrubPos >= 0) {
                                            root.seekTo(timelineRow.scrubPos);
                                            timelineRow.scrubPos = -1;
                                        }
                                    }

                                    onWheel: (wheel) => {
                                        wheel.accepted = true;
                                        root.resetInactivityTimer();
                                        const delta = wheel.angleDelta.y !== 0 ? (wheel.angleDelta.y > 0 ? 5 : -5) : (wheel.angleDelta.x > 0 ? 5 : -5);
                                        root.seekRelative(delta);
                                    }
                                }
                            }

                            Text {
                                text: root.formatTime(timelineRow.totalLen)
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
                                color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒮"
                                    color: prevMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
                                    font.pixelSize: 16
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: prevMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.resetInactivityTimer();
                                        root.activePlayer?.previous();
                                    }
                                }
                            }

                            // Play / Pause Circle Button
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                color: playMouse.containsMouse ? Qt.lighter(root.playerAccent, 1.15) : root.playerAccent
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
                                    id: playMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.resetInactivityTimer();
                                        root.activePlayer?.togglePlaying();
                                    }
                                }
                            }

                            // Next Track
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒭"
                                    color: nextMouse.containsMouse ? "#ffffff" : root.theme.textSecondary
                                    font.pixelSize: 16
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: nextMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.resetInactivityTimer();
                                        root.activePlayer?.next();
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 3: NOTIFICATION ALERT MORPH
                // ═══════════════════════════════════════════
                Item {
                    id: notificationView
                    anchors.fill: parent
                    visible: root.islandMode === "notification" || opacity > 0.0
                    opacity: root.islandMode === "notification" ? 1.0 : 0.0
                    scale: root.islandMode === "notification" ? 1.0 : 0.96
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    readonly property var notifData: Services.NotificationService.islandNotification

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // App Icon / Bell Badge
                        Rectangle {
                            width: 38
                            height: 38
                            radius: 19
                            color: Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1

                            IconImage {
                                id: notifIconImg
                                anchors.fill: parent
                                anchors.margins: 7
                                source: Quickshell.iconPath(notificationView.notifData?.appIcon ?? "", true)
                                visible: (notificationView.notifData?.appIcon ?? "") !== "" && status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰂚"
                                color: root.theme.accent
                                font.pixelSize: 18
                                font.family: root.font
                                visible: !notifIconImg.visible
                            }
                        }

                        // Text Column (Summary & Body)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                spacing: 6
                                Text {
                                    text: notificationView.notifData?.appName ?? "Notification"
                                    color: root.theme.accent
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.family: root.font
                                }

                                // Burst Notification Badge (+N)
                                Rectangle {
                                    visible: Services.NotificationService.unreadCount > 1
                                    height: 14
                                    radius: 7
                                    width: Math.max(14, burstText.implicitWidth + 8)
                                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)
                                    border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.60)
                                    border.width: 1

                                    Text {
                                        id: burstText
                                        anchors.centerIn: parent
                                        text: "+" + (Services.NotificationService.unreadCount - 1)
                                        color: "#ffffff"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.family: root.font
                                    }
                                }

                                Text {
                                    text: "• " + (notificationView.notifData?.timeStr ?? "")
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                }
                            }

                            Text {
                                text: notificationView.notifData?.summary ?? ""
                                color: root.theme.textPrimary
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.family: root.font
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: notificationView.notifData?.body ?? ""
                                color: root.theme.textSecondary
                                font.pixelSize: 11
                                font.family: root.font
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }
                        }

                        // Close Button
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: notifCloseM.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBg
                            border.color: Services.Aesthetic.innerCardBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: root.theme.textSecondary
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            MouseArea {
                                id: notifCloseM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.NotificationService.dismissIsland()
                            }
                        }
                    }

                    // Bottom Countdown Progress Bar (Refined centered capsule)
                    Rectangle {
                        id: countTrack
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 7
                        width: 160
                        height: 3
                        radius: 1.5
                        color: Services.Aesthetic.sliderTrackBg
                        clip: true

                        Rectangle {
                            id: countBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 1.5
                            color: root.theme.accent

                            NumberAnimation on width {
                                running: root.islandMode === "notification"
                                from: countTrack.width
                                to: 0
                                duration: 3000
                                easing.type: Easing.Linear
                            }
                        }
                    }

                    // Click entire notification to invoke default action & dismiss (or wheel-up to flick away)
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 36
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                Services.NotificationService.dismissIsland();
                                return;
                            }
                            const n = notificationView.notifData?.notif;
                            if (n) {
                                try { n.defaultAction(); } catch (e) {}
                            }
                            Services.NotificationService.dismissIsland();
                        }
                        onWheel: (wheel) => {
                            if (wheel.angleDelta.y > 0) {
                                wheel.accepted = true;
                                Services.NotificationService.dismissIsland();
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════
                // VIEW 4: OSD CAPSULE (Volume / Brightness)
                // ═══════════════════════════════════════════
                Item {
                    id: osdView
                    anchors.fill: parent
                    visible: root.islandMode === "osd" || opacity > 0.0
                    opacity: root.islandMode === "osd" ? 1.0 : 0.0
                    scale: root.islandMode === "osd" ? 1.0 : 0.96
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16
                        spacing: 12

                        // Circular Hardware Badge (32x32 circle)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.rgba(Services.OsdService.iconColor.r, Services.OsdService.iconColor.g, Services.OsdService.iconColor.b, Services.Aesthetic.preset === "oled" ? 0.16 : 0.12)
                            border.color: Qt.rgba(Services.OsdService.iconColor.r, Services.OsdService.iconColor.g, Services.OsdService.iconColor.b, Services.Aesthetic.preset === "oled" ? 0.32 : 0.24)
                            border.width: 1
                            Layout.alignment: Qt.AlignVCenter

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.OsdService.icon
                                color: Services.OsdService.iconColor
                                font.pixelSize: 15
                                font.family: root.font
                            }
                        }

                        // Middle Content Area
                        // Case A: Progress bar exists (Volume, Brightness, Battery level)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            visible: Services.OsdService.progress >= 0

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: Services.OsdService.title
                                    color: root.theme.textMuted
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    font.family: root.font
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Services.OsdService.valueText
                                    color: root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.family: root.font
                                }
                            }

                            // Capsule Slider Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Services.Aesthetic.sliderTrackBg
                                border.color: Services.Aesthetic.innerCardBorder
                                border.width: Services.Aesthetic.preset === "solid" ? 1 : 0
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: 3
                                    color: Services.OsdService.barColor
                                    width: Services.OsdService.progress >= 0 ? parent.width * Math.max(0, Math.min(1.0, Services.OsdService.progress)) : 0

                                    Behavior on width {
                                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }

                        // Case B: No progress bar (Power Profile, etc.)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            visible: Services.OsdService.progress < 0

                            Text {
                                text: Services.OsdService.title
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.family: root.font
                            }

                            Text {
                                text: Services.OsdService.valueText
                                color: root.theme.textPrimary
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.family: root.font
                            }
                        }
                    }
                }
            }

            // ── Detachable Satellite Pill (Dual-Pill Splitting) ──
            Rectangle {
                id: satellitePill
                anchors.left: islandContainer.right
                anchors.leftMargin: 8
                anchors.verticalCenter: islandContainer.verticalCenter
                width: 28
                height: 28
                radius: 14
                clip: true
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                visible: root.satelliteActive || opacity > 0.01
                opacity: root.satelliteActive ? 1.0 : 0.0
                scale: root.satelliteActive ? 1.0 : 0.0

                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.25 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                // Secondary Media Activity Disc
                Item {
                    anchors.fill: parent
                    visible: root.satelliteType === "media"

                    Rectangle {
                        id: satArtBox
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        radius: 5
                        color: Qt.rgba(0.12, 0.12, 0.15, 0.8)
                        border.color: Services.Aesthetic.innerCardBorder
                        border.width: 1

                        Image {
                            id: satArt
                            anchors.fill: parent
                            source: root.displayTrackArt
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            asynchronous: true
                            cache: true
                        }

                        Rectangle {
                            id: satArtMask
                            anchors.fill: parent
                            radius: 5
                            color: "#ffffff"
                            antialiasing: true
                            visible: false
                            layer.enabled: true
                        }

                        MultiEffect {
                            id: satArtEffect
                            anchors.fill: parent
                            source: satArt
                            maskEnabled: true
                            maskSource: satArtMask
                            visible: satArt.status === Image.Ready && root.displayTrackArt !== ""
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: "transparent"
                            border.color: satArtBox.border.color
                            border.width: satArtBox.border.width
                            antialiasing: true
                            z: 2
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰝚"
                            color: root.playerAccent
                            font.pixelSize: 11
                            font.family: root.font
                            visible: !satArtEffect.visible
                        }
                    }

                    // Mini 2-bar Cava equalizer
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        anchors.right: parent.right
                        anchors.rightMargin: 3
                        spacing: 1.5
                        visible: root.isMediaPlaying

                        Rectangle {
                            width: 2
                            height: Math.max(2.5, root.cavaBar1 * 8)
                            radius: 1
                            color: root.playerAccent
                            anchors.bottom: parent.bottom
                        }
                        Rectangle {
                            width: 2
                            height: Math.max(2.5, root.cavaBar2 * 8)
                            radius: 1
                            color: root.playerAccent
                            anchors.bottom: parent.bottom
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                root.isMediaExpanded = true;
                            } else {
                                root.activePlayer?.togglePlaying();
                            }
                        }
                        onDoubleClicked: root.isMediaExpanded = true
                    }
                }

                // Secondary Notification Activity Disc
                Item {
                    anchors.fill: parent
                    visible: root.satelliteType === "notification"

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        color: root.theme.accent
                        font.pixelSize: 13
                        font.family: root.font
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        width: 5
                        height: 5
                        radius: 2.5
                        color: root.theme.accent
                        visible: Services.NotificationService.unreadCount > 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.NotificationService.dismissIsland()
                    }
                }
            }
        }
    }
}
