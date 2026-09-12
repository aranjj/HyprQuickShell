import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"
    property bool _ready: false

    // ── PipeWire Audio Monitoring ───────────────────
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumeChanged() {
            if (root._ready && Pipewire.defaultAudioSink?.audio) {
                const vol = Math.round(Pipewire.defaultAudioSink.audio.volume * 100);
                const muted = Pipewire.defaultAudioSink.audio.muted;
                Services.OsdService.showVolume(vol, muted);
            }
        }

        function onMutedChanged() {
            if (root._ready && Pipewire.defaultAudioSink?.audio) {
                const vol = Math.round(Pipewire.defaultAudioSink.audio.volume * 100);
                const muted = Pipewire.defaultAudioSink.audio.muted;
                Services.OsdService.showVolume(vol, muted);
            }
        }
    }

    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null

        function onVolumeChanged() {
            if (root._ready && Pipewire.defaultAudioSource?.audio) {
                const vol = Math.round(Pipewire.defaultAudioSource.audio.volume * 100);
                const muted = Pipewire.defaultAudioSource.audio.muted;
                Services.OsdService.showMic(vol, muted);
            }
        }

        function onMutedChanged() {
            if (root._ready && Pipewire.defaultAudioSource?.audio) {
                const vol = Math.round(Pipewire.defaultAudioSource.audio.volume * 100);
                const muted = Pipewire.defaultAudioSource.audio.muted;
                Services.OsdService.showMic(vol, muted);
            }
        }
    }

    // ── Hardware Backlight Monitoring ───────────────
    property real maxBrightness: 1
    FileView {
        id: brightnessFile
        path: ""
        watchChanges: true
        onFileChanged: brightReadProc.running = true
    }

    Process {
        id: brightReadProc
        command: ["cat", "/sys/class/backlight/intel_backlight/brightness"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = parseInt(text.trim());
                if (!isNaN(cur) && root.maxBrightness > 0) {
                    const pct = Math.round((cur / root.maxBrightness) * 100);
                    if (root._ready && !Services.OsdService.suppressBrightness) {
                        Services.OsdService.showBrightness(pct);
                    }
                }
            }
        }
    }

    Process {
        id: backlightDiscovery
        command: ["sh", "-c", "p=$(ls -d /sys/class/backlight/*/brightness 2>/dev/null | head -1); [ -n \"$p\" ] && echo \"$p\" && cat \"${p%brightness}max_brightness\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    const max = parseInt(lines[1]);
                    if (!isNaN(max) && max > 0) root.maxBrightness = max;
                    brightnessFile.path = lines[0];
                    brightReadProc.command = ["cat", lines[0]];
                }
                readyTimer.start();
            }
        }
    }

    // Avoid triggering OSD during initial startup discovery
    Timer {
        id: readyTimer
        interval: 1200
        onTriggered: root._ready = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property ShellScreen modelData
            screen: modelData

            visible: false // Handled directly by Dynamic Island morphing!
            focusable: false
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-osd"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: osdPill }

            anchors {
                bottom: true
            }

            margins {
                bottom: 50
            }

            implicitWidth: osdPill.width + 20
            implicitHeight: 64

            // ── OSD Pill Bezel ──────────────────────────
            Rectangle {
                id: osdPill
                anchors.centerIn: parent
                width: 250
                height: 52
                radius: 26
                color: Qt.rgba(0.09, 0.09, 0.14, 0.78)
                border.color: Qt.rgba(1, 1, 1, 0.16)
                border.width: 1

                opacity: Services.OsdService.visible ? 1 : 0
                scale: Services.OsdService.visible ? 1 : 0.92

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Icon Badge
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: Services.OsdService.icon
                            color: Services.OsdService.iconColor
                            font.pixelSize: 17
                            font.family: root.font
                        }
                    }

                    // Content: Labels and Progress Bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: Services.OsdService.title
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                font.weight: Font.Medium
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: Services.OsdService.valueText
                                color: root.theme.textPrimary
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.DemiBold
                            }
                        }

                        // Progress Bar (hidden when progress < 0)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 5
                            radius: 2.5
                            color: root.theme.barBg
                            visible: Services.OsdService.progress >= 0

                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * Services.OsdService.progress))
                                height: parent.height
                                radius: 2.5
                                color: Services.OsdService.barColor

                                Behavior on width {
                                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
