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
            id: toolbarWindow
            required property ShellScreen modelData
            screen: modelData

            visible: Services.ScreenshotService.toolbarVisible
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "quickshell-screenshot-toolbar"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: toolbarCard }

            anchors {
                bottom: true
            }
            margins {
                bottom: 36
            }

            implicitWidth: toolbarCard.implicitWidth + 20
            implicitHeight: toolbarCard.implicitHeight + 20

            // Keyboard shortcuts
            Item {
                focus: true
                Keys.onEscapePressed: Services.ScreenshotService.toolbarVisible = false
                Keys.onDigit1Pressed: Services.ScreenshotService.capture("fullscreen", Services.ScreenshotService.delayTimer)
                Keys.onDigit2Pressed: Services.ScreenshotService.capture("window", Services.ScreenshotService.delayTimer)
                Keys.onDigit3Pressed: Services.ScreenshotService.capture("region", Services.ScreenshotService.delayTimer)
            }

            // Floating Glass Capsule
            Rectangle {
                id: toolbarCard
                anchors.centerIn: parent
                implicitHeight: 48
                implicitWidth: contentRow.implicitWidth + 20
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth

                RowLayout {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 6

                    // ── 1. Full Screen ──────────────────────
                    Rectangle {
                        implicitHeight: 34
                        implicitWidth: rowFull.implicitWidth + 20
                        radius: 10
                        color: mFull.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: mFull.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40) : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: rowFull
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰹑"; color: mFull.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 14; font.family: root.font }
                            Text { text: "Full Screen"; color: mFull.containsMouse ? "#ffffff" : root.theme.textPrimary; font.pixelSize: 12; font.family: root.font; font.weight: Font.Medium }
                        }

                        MouseArea {
                            id: mFull; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("fullscreen", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // ── 2. Window ───────────────────────────
                    Rectangle {
                        implicitHeight: 34
                        implicitWidth: rowWin.implicitWidth + 20
                        radius: 10
                        color: mWin.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: mWin.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40) : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: rowWin
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰍹"; color: mWin.containsMouse ? "#ffffff" : root.theme.textSecondary; font.pixelSize: 14; font.family: root.font }
                            Text { text: "Window"; color: mWin.containsMouse ? "#ffffff" : root.theme.textPrimary; font.pixelSize: 12; font.family: root.font; font.weight: Font.Medium }
                        }

                        MouseArea {
                            id: mWin; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("window", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // ── 3. Select Region ────────────────────
                    Rectangle {
                        implicitHeight: 34
                        implicitWidth: rowReg.implicitWidth + 20
                        radius: 10
                        color: mReg.containsMouse ? root.theme.accent : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)
                        border.color: mReg.containsMouse ? root.theme.accent : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: rowReg
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰒉"; color: "#ffffff"; font.pixelSize: 14; font.family: root.font }
                            Text { text: "Select Region"; color: "#ffffff"; font.pixelSize: 12; font.family: root.font; font.weight: Font.DemiBold }
                        }

                        MouseArea {
                            id: mReg; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("region", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // Divider
                    Rectangle { width: 1; implicitHeight: 20; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Timer Delay ──────────────────────
                    Rectangle {
                        implicitHeight: 30
                        implicitWidth: rowTimer.implicitWidth + 14
                        radius: 8
                        color: mTimer.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: rowTimer
                            anchors.centerIn: parent
                            spacing: 5
                            Text { text: "󰔛"; color: Services.ScreenshotService.delayTimer > 0 ? root.theme.accentOrange : root.theme.textMuted; font.pixelSize: 12; font.family: root.font }
                            Text {
                                text: Services.ScreenshotService.delayTimer === 0 ? "Off" : Services.ScreenshotService.delayTimer + "s"
                                color: Services.ScreenshotService.delayTimer > 0 ? "#ffffff" : root.theme.textSecondary
                                font.pixelSize: 11; font.family: root.font
                                font.weight: Services.ScreenshotService.delayTimer > 0 ? Font.DemiBold : Font.Normal
                            }
                        }

                        MouseArea {
                            id: mTimer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const cur = Services.ScreenshotService.delayTimer;
                                Services.ScreenshotService.delayTimer = cur === 0 ? 3 : (cur === 3 ? 5 : (cur === 5 ? 10 : 0));
                            }
                        }
                    }

                    // Divider
                    Rectangle { width: 1; implicitHeight: 20; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Close ────────────────────────────
                    Rectangle {
                        implicitWidth: 26; implicitHeight: 26; radius: 13
                        color: mClose.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text { anchors.centerIn: parent; text: "✕"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }

                        MouseArea {
                            id: mClose; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.toolbarVisible = false
                        }
                    }
                }
            }
        }
    }
}
