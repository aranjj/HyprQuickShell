import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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

    // ── Active MPRIS player ──────────────────────────────
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
        running: root.hasMedia && root.isMediaPlaying
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

    // ── Priority State Machine ───────────────────────────
    // Priority: Hardware OSD > Notification Alert > Media Expanded > Media Compact > Hidden
    readonly property string islandMode: {
        if (hasOsd) return "osd";
        if (hasNotification) return "notification";
        if (hasMedia && isMediaExpanded) return "mediaExpanded";
        if (hasMedia) return "mediaCompact";
        return "hidden";
    }

    // ── Satellite (Dual-Pill) State Engine ───────────────
    readonly property bool satelliteActive: {
        if (islandMode === "osd") return hasMedia || hasNotification;
        if (islandMode === "notification") return hasMedia;
        return false;
    }

    readonly property string satelliteType: {
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

            visible: root.isMediaExpanded
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
            visible: root.islandMode !== "hidden"

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

            // ── Island Cluster (Main Pill + Detachable Satellite Pill) ──
            Item {
                id: islandCluster
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                height: Math.max(islandContainer.height, satellitePill.height)
                width: islandContainer.width + (root.satelliteActive ? (8 + satellitePill.width) : 0)

                Behavior on width {
                    NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.08 }
                }

                // ── Main Morphing Island Pill ─────────────────
                Rectangle {
                    id: islandContainer
                    anchors.left: parent.left
                    anchors.top: parent.top
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
                        if (root.islandMode === "osd") return 240;
                        if (root.islandMode === "mediaCompact") return Math.max(200, Math.min(350, compactContent.implicitWidth + 24));
                        return 0;
                    }

                    height: {
                        if (root.islandMode === "notification") return 74;
                        if (root.islandMode === "mediaExpanded") return 190;
                        if (root.islandMode === "osd") return 28;
                        if (root.islandMode === "mediaCompact") return 28;
                        return 0;
                    }

                    radius: {
                        if (root.islandMode === "notification") return 24;
                        if (root.islandMode === "mediaExpanded") return 24;
                        if (root.islandMode === "osd") return 14;
                        if (root.islandMode === "mediaCompact") return 14;
                        return 0;
                    }

                color: root.islandMode === "mediaExpanded" ? Qt.rgba(0.04, 0.04, 0.06, 0.98) : "#000000"
                border.color: root.islandMode === "notification" ? Qt.rgba(0, 122, 255, 0.45) : (root.islandMode === "osd" ? Qt.rgba(1, 1, 1, 0.20) : (root.islandMode === "mediaExpanded" ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)))
                border.width: 1

                Behavior on border.color { ColorAnimation { duration: 200 } }

                // Organic Spring Physics (Apple-grade micro-spring)
                Behavior on width {
                    NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 }
                }
                Behavior on height {
                    NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 }
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

                        // Thumbnail
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 4.5
                            clip: true
                            color: Qt.rgba(0.12, 0.12, 0.15, 0.8)
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: compactArt
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
                                font.pixelSize: 11
                                font.family: root.font
                                visible: !compactArt.visible
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
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
                                width: 52
                                height: 52
                                radius: 12
                                clip: true
                                color: Qt.rgba(0, 0, 0, 0.35)
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                Image {
                                    id: expandedArt
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
                                    visible: !expandedArt.visible
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
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                            border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.4)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "󰂚"
                                color: root.theme.accent
                                font.pixelSize: 18
                                font.family: root.font
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
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.family: root.font
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: notificationView.notifData?.body ?? ""
                                color: "#b0b0b8"
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
                            color: notifCloseM.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
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
                        color: Qt.rgba(1, 1, 1, 0.12)
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
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        // Hardware Icon
                        Text {
                            text: Services.OsdService.icon
                            color: Services.OsdService.iconColor
                            font.pixelSize: 13
                            font.family: root.font
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Case A: Progress bar exists (Volume, Brightness, Battery level)
                        Rectangle {
                            visible: Services.OsdService.progress >= 0
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            height: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.18)
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

                        // Case B: No progress bar (Power Profile, etc.)
                        Text {
                            visible: Services.OsdService.progress < 0
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: Services.OsdService.title
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            elide: Text.ElideRight
                        }

                        // Numeric percentage or mode text
                        Text {
                            text: Services.OsdService.valueText
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.family: root.font
                            Layout.alignment: Qt.AlignVCenter
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
                color: "#000000"
                border.color: root.satelliteType === "media" ? Qt.rgba(root.playerAccent.r, root.playerAccent.g, root.playerAccent.b, 0.40) : Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

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
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        radius: 10
                        clip: true
                        color: Qt.rgba(0.12, 0.12, 0.15, 0.8)

                        Image {
                            id: satArt
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
                            font.pixelSize: 11
                            font.family: root.font
                            visible: !satArt.visible
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
}
