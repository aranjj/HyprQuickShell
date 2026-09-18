import Quickshell
import Quickshell.Wayland
import QtQuick
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
            WlrLayershell.keyboardFocus: (Services.ScreenshotService.directSnipMode || Services.ScreenshotService.isSelecting) ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "quickshell-screenshot-toolbar"
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // ── Frozen Display Background ─────────────────
            Image {
                id: frozenView
                anchors.fill: parent
                source: Services.ScreenshotService.freezeImagePath !== "" ? ("file://" + Services.ScreenshotService.freezeImagePath + "?v=" + Services.ScreenshotService.freezeVersion) : ""
                sourceClipRect: Qt.rect(modelData.x, modelData.y, modelData.width, modelData.height)
                fillMode: Image.PreserveAspectCrop
                cache: false
                visible: Services.ScreenshotService.freezeImagePath !== ""
            }

            // Subtle Dimming Overlay (indicating freeze mode)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.16)
                visible: Services.ScreenshotService.freezeImagePath !== ""
            }

            // Click outside toolbar capsule to dismiss
            MouseArea {
                anchors.fill: parent
                enabled: !Services.ScreenshotService.isSelecting && !Services.ScreenshotService.directSnipMode
                onClicked: Services.ScreenshotService.closeToolbar()
            }

            // Keyboard shortcuts (1 = Full, 2 = Window, 3 = Region, Esc = Close)
            Item {
                focus: toolbarWindow.visible && !Services.ScreenshotService.directSnipMode && !Services.ScreenshotService.isSelecting
                Keys.onEscapePressed: Services.ScreenshotService.closeToolbar()
                Keys.onDigit1Pressed: Services.ScreenshotService.capture("fullscreen", Services.ScreenshotService.delayTimer)
                Keys.onDigit2Pressed: Services.ScreenshotService.capture("window", Services.ScreenshotService.delayTimer)
                Keys.onDigit3Pressed: Services.ScreenshotService.capture("region", Services.ScreenshotService.delayTimer)
            }

            BackgroundEffect.blurRegion: Region { item: toolbarCard }

            // Floating Glass Capsule
            Rectangle {
                id: toolbarCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 36

                implicitHeight: 52
                implicitWidth: contentRow.implicitWidth + 24
                radius: 18
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                visible: !Services.ScreenshotService.isSelecting && !Services.ScreenshotService.directSnipMode
                opacity: (!Services.ScreenshotService.isSelecting && !Services.ScreenshotService.directSnipMode) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                // Prevent click dismissal inside card
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 6

                    // ═══════════════════════════════════════════
                    // 1. THREE MAIN CAPTURE BUTTONS (NO DEFAULT SELECTION)
                    // ═══════════════════════════════════════════

                    // 1. Full Screen
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: rowFull.implicitWidth + 24
                        radius: 10
                        color: mFull.pressed ? root.theme.accent
                             : (mFull.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: mFull.pressed || mFull.containsMouse ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        Row {
                            id: rowFull
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰹑"
                                color: mFull.pressed ? "#ffffff" : (mFull.containsMouse ? root.theme.accent : root.theme.textSecondary)
                                font.pixelSize: 14
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Full Screen"
                                color: mFull.pressed ? "#ffffff" : (mFull.containsMouse ? "#ffffff" : root.theme.textPrimary)
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: mFull
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("fullscreen", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // 2. Window
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: rowWin.implicitWidth + 24
                        radius: 10
                        color: mWin.pressed ? root.theme.accent
                             : (mWin.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: mWin.pressed || mWin.containsMouse ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        Row {
                            id: rowWin
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰖲"
                                color: mWin.pressed ? "#ffffff" : (mWin.containsMouse ? root.theme.accent : root.theme.textSecondary)
                                font.pixelSize: 14
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Window"
                                color: mWin.pressed ? "#ffffff" : (mWin.containsMouse ? "#ffffff" : root.theme.textPrimary)
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: mWin
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("window", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // 3. Selection
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: rowReg.implicitWidth + 24
                        radius: 10
                        color: mReg.pressed ? root.theme.accent
                             : (mReg.containsMouse ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: mReg.pressed || mReg.containsMouse ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        Row {
                            id: rowReg
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰒉"
                                color: mReg.pressed ? "#ffffff" : (mReg.containsMouse ? root.theme.accent : root.theme.textSecondary)
                                font.pixelSize: 14
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Selection"
                                color: mReg.pressed ? "#ffffff" : (mReg.containsMouse ? "#ffffff" : root.theme.textPrimary)
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: mReg
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.capture("region", Services.ScreenshotService.delayTimer)
                        }
                    }

                    // Divider
                    Rectangle {
                        width: 1
                        height: 20
                        color: Qt.rgba(1, 1, 1, 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // ═══════════════════════════════════════════
                    // 2. TIMER & FOLDER
                    // ═══════════════════════════════════════════

                    // Timer Delay
                    Rectangle {
                        readonly property bool hasDelay: Services.ScreenshotService.delayTimer > 0
                        implicitHeight: 36
                        implicitWidth: rowTimer.implicitWidth + 20
                        radius: 10
                        color: hasDelay ? Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.22)
                                        : (mTimer.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: hasDelay ? root.theme.accentOrange : (mTimer.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        Row {
                            id: rowTimer
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "󰔛"
                                color: parent.parent.hasDelay ? root.theme.accentOrange : (mTimer.containsMouse ? "#ffffff" : root.theme.textMuted)
                                font.pixelSize: 13
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: Services.ScreenshotService.delayTimer === 0 ? "Timer: Off" : (Services.ScreenshotService.delayTimer + "s Delay")
                                color: parent.parent.hasDelay ? "#ffffff" : (mTimer.containsMouse ? "#ffffff" : root.theme.textSecondary)
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: parent.parent.hasDelay ? Font.DemiBold : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: mTimer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const cur = Services.ScreenshotService.delayTimer;
                                Services.ScreenshotService.delayTimer = cur === 0 ? 3 : (cur === 3 ? 5 : (cur === 5 ? 10 : 0));
                            }
                        }
                    }

                    // Screenshots Folder
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: 36
                        radius: 10
                        color: mFolder.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: mFolder.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰉋"
                            color: mFolder.containsMouse ? "#ffffff" : root.theme.textMuted
                            font.pixelSize: 15
                            font.family: root.font
                        }

                        MouseArea {
                            id: mFolder
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.openScreenshotsFolder()
                        }
                    }

                    // Divider
                    Rectangle {
                        width: 1
                        height: 20
                        color: Qt.rgba(1, 1, 1, 0.12)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // ═══════════════════════════════════════════
                    // 3. CLOSE
                    // ═══════════════════════════════════════════

                    // Close (✕)
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: 36
                        radius: 18
                        color: mClose.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: mClose.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: mClose.containsMouse ? "#ffffff" : root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                        }

                        MouseArea {
                            id: mClose
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenshotService.closeToolbar()
                        }
                    }
                }
            }
        }
    }
}
