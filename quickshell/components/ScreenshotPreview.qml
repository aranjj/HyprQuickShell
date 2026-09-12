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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: previewWindow
            required property ShellScreen modelData
            screen: modelData

            visible: Services.ScreenshotService.previewVisible && Services.ScreenshotService.lastScreenshotPath !== ""
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

            implicitWidth: 268
            implicitHeight: 182

            // macOS Floating Screenshot Thumbnail Card
            Rectangle {
                id: card
                anchors.fill: parent
                radius: 16
                color: Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.80)
                border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.25)
                border.width: 1
                clip: true

                // Scale / entrance animation
                scale: Services.ScreenshotService.previewVisible ? 1.0 : 0.88
                opacity: Services.ScreenshotService.previewVisible ? 1.0 : 0.0
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                // Thumbnail Container
                Rectangle {
                    id: thumbContainer
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 5
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.4)
                    clip: true

                    Image {
                        id: thumbImg
                        anchors.fill: parent
                        source: Services.ScreenshotService.lastScreenshotPath ? ("file://" + Services.ScreenshotService.lastScreenshotPath) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }

                    // HoverHandler tracks hover across entire container
                    HoverHandler {
                        id: cardHover
                        onHoveredChanged: Services.ScreenshotService.previewHovered = hovered
                    }

                    // Click on image area to open screenshot
                    MouseArea {
                        anchors.fill: parent
                        anchors.bottomMargin: 36
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.ScreenshotService.openLastScreenshot()
                    }

                    // Action Bar — visible whenever the card is hovered
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 36
                        color: Qt.rgba(root.theme.surfaceDim.r, root.theme.surfaceDim.g, root.theme.surfaceDim.b, 0.90)
                        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.20)
                        border.width: 1
                        opacity: cardHover.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            // Open in viewer
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: openM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "󰋩"; color: "#ffffff"; font.pixelSize: 13; font.family: root.font }
                                MouseArea {
                                    id: openM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.ScreenshotService.openLastScreenshot()
                                }
                            }

                            // Show in Dolphin
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: folM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "󰉋"; color: "#ffffff"; font.pixelSize: 13; font.family: root.font }
                                MouseArea {
                                    id: folM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.ScreenshotService.openScreenshotsFolder()
                                }
                            }

                            // Copy to clipboard
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: copyM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "󰅍"; color: "#ffffff"; font.pixelSize: 13; font.family: root.font }
                                MouseArea {
                                    id: copyM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.ScreenshotService.copyLastToClipboard()
                                }
                            }

                            // Delete (Trash)
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: delM.containsMouse ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "󰩹"; color: delM.containsMouse ? root.theme.accentRed : "#ffffff"; font.pixelSize: 13; font.family: root.font }
                                MouseArea {
                                    id: delM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.ScreenshotService.deleteLastScreenshot()
                                }
                            }

                            // Dismiss
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: disM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "✕"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                                MouseArea {
                                    id: disM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.ScreenshotService.dismissPreview()
                                }
                            }
                        }
                    }
                }

                // Auto-dismiss Timer Bar (at bottom edge)
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 2
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: parent.width * Math.max(0, Math.min(1.0, Services.ScreenshotService.previewProgress))
                        color: root.theme.accent
                    }
                }
            }
        }
    }
}
