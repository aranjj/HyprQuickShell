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
            id: powerMenuWindow
            required property ShellScreen modelData
            screen: modelData

            visible: Services.SystemService.powerMenuOpen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-power-menu"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: powerCard }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // Darkened backdrop (click to dismiss)
            Rectangle {
                anchors.fill: parent
                color: Services.Aesthetic.backdropColor

                MouseArea {
                    anchors.fill: parent
                    onClicked: Services.SystemService.powerMenuOpen = false
                }
            }

            // Power Menu Card
            Rectangle {
                id: powerCard
                anchors.centerIn: parent
                width: 440
                height: 180
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth

                // Stop dismissal click from propagating
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Title
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Power Options"
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: closeMouse.containsMouse ? root.theme.pillHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: root.theme.textSecondary
                                font.pixelSize: 12
                                font.family: root.font
                            }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemService.powerMenuOpen = false
                            }
                        }
                    }

                    // Action Buttons Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // Lock
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 80
                            radius: 14
                            color: lockMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰌾"
                                    color: root.theme.accent
                                    font.pixelSize: 22
                                    font.family: root.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Lock"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: lockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.powerMenuOpen = false;
                                    Services.SystemService.runCmd("quickshell ipc call lock lock");
                                }
                            }
                        }

                        // Suspend
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 80
                            radius: 14
                            color: suspMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰤄"
                                    color: root.theme.accentMauve
                                    font.pixelSize: 22
                                    font.family: root.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Sleep"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: suspMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.powerMenuOpen = false;
                                    Services.SystemService.runCmd("systemctl suspend");
                                }
                            }
                        }

                        // Logout
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 80
                            radius: 14
                            color: logoutMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰍃"
                                    color: root.theme.accentOrange
                                    font.pixelSize: 22
                                    font.family: root.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Logout"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: logoutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.powerMenuOpen = false;
                                    Services.SystemService.runCmd("hyprctl dispatch \"hl.dsp.exit()\"");
                                }
                            }
                        }

                        // Reboot
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 80
                            radius: 14
                            color: rebMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰜉"
                                    color: root.theme.accentYellow
                                    font.pixelSize: 22
                                    font.family: root.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Reboot"
                                    color: root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: rebMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.powerMenuOpen = false;
                                    Services.SystemService.runCmd("systemctl reboot");
                                }
                            }
                        }

                        // Shutdown
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 80
                            radius: 14
                            color: shutMouse.containsMouse ? root.theme.accentRed : root.theme.pillBg
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "⏻"
                                    color: shutMouse.containsMouse ? "#ffffff" : root.theme.accentRed
                                    font.pixelSize: 22
                                    font.family: root.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Power Off"
                                    color: shutMouse.containsMouse ? "#ffffff" : root.theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: shutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.SystemService.powerMenuOpen = false;
                                    Services.SystemService.runCmd("systemctl poweroff");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
