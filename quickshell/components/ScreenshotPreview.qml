import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    property bool isOpen: Services.ScreenshotService.previewVisible && Services.ScreenshotService.lastScreenshotPath !== ""
    onIsOpenChanged: {
        if (!isOpen) {
            closeAnimTimer.restart();
            justCopied = false;
        } else {
            closeAnimTimer.stop();
        }
    }

    property bool justCopied: false
    Timer {
        id: copyResetTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.justCopied = false;
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 180
        repeat: false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: previewWindow
            required property ShellScreen modelData
            screen: modelData

            visible: (root.isOpen || closeAnimTimer.running) && Services.ScreenshotService.lastScreenshotPath !== ""
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-screenshot-preview"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: card }

            anchors {
                bottom: true
                right: true
            }
            margins {
                bottom: 28
                right: 28
            }

            implicitWidth: 284
            implicitHeight: 196

            // Floating Screenshot Thumbnail Card
            Rectangle {
                id: card
                anchors.fill: parent
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                // Active overlay state for thumbnail center
                property string activeOverlayIcon: ""
                property string activeOverlayText: ""
                property color activeOverlayColor: "#ffffff"

                function setOverlay(icon, text, col) {
                    activeOverlayIcon = icon;
                    activeOverlayText = text;
                    activeOverlayColor = col !== undefined ? col : "#ffffff";
                }

                function clearOverlay() {
                    activeOverlayIcon = "";
                    activeOverlayText = "";
                    activeOverlayColor = "#ffffff";
                }

                // Scale / entrance & exit animation
                scale: root.isOpen ? 1.0 : 0.88
                opacity: root.isOpen ? 1.0 : 0.0
                transformOrigin: Item.BottomRight

                Behavior on scale {
                    NumberAnimation {
                        duration: root.isOpen ? 220 : 160
                        easing.type: root.isOpen ? Easing.OutBack : Easing.InQuad
                        easing.overshoot: 1.06
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutQuad
                    }
                }

                // HoverHandler tracks hover across entire card to pause dismiss timer
                HoverHandler {
                    id: cardHover
                    onHoveredChanged: Services.ScreenshotService.previewHovered = hovered
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // ── Thumbnail Container ─────────────────
                    Rectangle {
                        id: thumbContainer
                        width: parent.width
                        height: 130
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0.45)
                        border.color: Qt.rgba(255, 255, 255, 0.10)
                        border.width: 1
                        clip: true

                        Image {
                            id: thumbImg
                            anchors.fill: parent
                            source: Services.ScreenshotService.lastScreenshotPath ? ("file://" + Services.ScreenshotService.lastScreenshotPath) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }

                        // Centered Action Overlay (appears when hovering buttons or thumbnail)
                        readonly property bool showOverlay: card.activeOverlayText !== "" || imgHover.hovered
                        readonly property string currentIcon: card.activeOverlayIcon !== "" ? card.activeOverlayIcon : "󰋩"
                        readonly property string currentText: card.activeOverlayText !== "" ? card.activeOverlayText : "Open Image"
                        readonly property color currentColor: card.activeOverlayText !== "" ? card.activeOverlayColor : "#ffffff"

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, thumbContainer.showOverlay ? 0.42 : 0.0)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                opacity: thumbContainer.showOverlay ? 1.0 : 0.0
                                scale: thumbContainer.showOverlay ? 1.0 : 0.94
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                Text {
                                    text: thumbContainer.currentIcon
                                    color: thumbContainer.currentColor
                                    font.pixelSize: 18
                                    font.family: root.font
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                Text {
                                    text: thumbContainer.currentText
                                    color: thumbContainer.currentColor
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    font.family: root.font
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                            }
                        }

                        HoverHandler {
                            id: imgHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.openLastScreenshot()
                        }
                    }

                    // ── Auto-dismiss Progress Bar ───────────
                    // Width matches thumbnail container; perfectly aligned within card margins
                    Rectangle {
                        id: timerTrack
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.rgba(255, 255, 255, 0.10)
                        clip: true

                        Rectangle {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: parent.width * Math.max(0, Math.min(1.0, Services.ScreenshotService.previewProgress))
                            radius: 1.5
                            color: Services.ScreenshotService.previewHovered ? root.theme.textMuted : root.theme.accent

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    // ── Action Controls Row ─────────────────
                    Item {
                        id: actionControlsItem
                        width: parent.width
                        height: 34

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            // 1. Open Image Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 8
                                color: openM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (openM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
                                border.color: openM.containsMouse ? Qt.rgba(255, 255, 255, 0.24) : Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1
                                scale: openM.pressed ? 0.94 : (openM.containsMouse ? 1.04 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰋩"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: openM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: card.setOverlay("󰋩", "Open Image", "#ffffff")
                                    onExited: card.clearOverlay()
                                    onClicked: Services.ScreenshotService.openLastScreenshot()
                                }
                            }

                            // 2. Open Folder Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 8
                                color: folM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (folM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
                                border.color: folM.containsMouse ? Qt.rgba(255, 255, 255, 0.24) : Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1
                                scale: folM.pressed ? 0.94 : (folM.containsMouse ? 1.04 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰉋"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: folM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: card.setOverlay("󰉋", "Open Folder", "#ffffff")
                                    onExited: card.clearOverlay()
                                    onClicked: Services.ScreenshotService.openScreenshotsFolder()
                                }
                            }

                            // 3. Copy to Clipboard Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 8
                                color: copyM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (root.justCopied ? Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.25) : (copyM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)))
                                border.color: root.justCopied ? root.theme.accentGreen : (copyM.containsMouse ? Qt.rgba(255, 255, 255, 0.24) : Qt.rgba(255, 255, 255, 0.08))
                                border.width: 1
                                scale: copyM.pressed ? 0.94 : (copyM.containsMouse ? 1.04 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.justCopied ? "󰄬" : "󰅍"
                                    color: root.justCopied ? root.theme.accentGreen : "#ffffff"
                                    font.pixelSize: 13
                                    font.family: root.font
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: copyM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        if (root.justCopied) {
                                            card.setOverlay("󰄬", "Copied to Clipboard", root.theme.accentGreen);
                                        } else {
                                            card.setOverlay("󰅍", "Copy to Clipboard", "#ffffff");
                                        }
                                    }
                                    onExited: card.clearOverlay()
                                    onClicked: {
                                        Services.ScreenshotService.copyLastToClipboard();
                                        root.justCopied = true;
                                        copyResetTimer.restart();
                                        card.setOverlay("󰄬", "Copied to Clipboard", root.theme.accentGreen);
                                    }
                                }
                            }

                            // 4. Delete Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 8
                                color: delM.pressed ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.35) : (delM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.22) : Qt.rgba(1, 1, 1, 0.07))
                                border.color: delM.containsMouse ? root.theme.accentRed : Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1
                                scale: delM.pressed ? 0.94 : (delM.containsMouse ? 1.04 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰩹"
                                    color: delM.containsMouse ? root.theme.accentRed : "#ffffff"
                                    font.pixelSize: 13
                                    font.family: root.font
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: delM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: card.setOverlay("󰩹", "Delete Screenshot", root.theme.accentRed)
                                    onExited: card.clearOverlay()
                                    onClicked: Services.ScreenshotService.deleteLastScreenshot()
                                }
                            }

                            // 5. Cross / Close Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 8
                                color: disM.pressed ? Qt.rgba(1, 1, 1, 0.22) : (disM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
                                border.color: disM.containsMouse ? Qt.rgba(255, 255, 255, 0.24) : Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1
                                scale: disM.pressed ? 0.94 : (disM.containsMouse ? 1.04 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: disM.containsMouse ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 11
                                    font.family: root.font
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: disM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: card.setOverlay("✕", "Close Preview", "#ffffff")
                                    onExited: card.clearOverlay()
                                    onClicked: Services.ScreenshotService.dismissPreview()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
