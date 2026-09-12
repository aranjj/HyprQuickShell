import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: aboutWin
            required property ShellScreen modelData
            screen: modelData

            visible: Services.SystemService.aboutDialogOpen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "quickshell-about-dialog"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: dialogCard }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Dimmed backdrop click to dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: Services.SystemService.aboutDialogOpen = false
            }

            // ── macOS "About This Mac" Card ─────────────
            Rectangle {
                id: dialogCard
                width: 430
                implicitHeight: cardContent.implicitHeight + 42
                anchors.centerIn: parent
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                // Prevent backdrop clicks from closing inside the card
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                // Top-right close button
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    width: 24
                    height: 24
                    radius: 12
                    color: closeM.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: root.theme.textMuted
                        font.pixelSize: 10
                        font.family: root.font
                    }

                    MouseArea {
                        id: closeM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.SystemService.aboutDialogOpen = false
                    }
                }

                ColumnLayout {
                    id: cardContent
                    width: parent.width - 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 22
                    spacing: 12

                    // ── OS Logo ─────────────────────────────
                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        Layout.alignment: Qt.AlignHCenter
                        radius: 26
                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                        border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.SystemService.distroGlyph
                            color: root.theme.accent
                            font.pixelSize: 30
                            font.family: root.font
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // ── Title & OS Info ─────────────────────
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2

                        Text {
                            text: Services.SystemService.distroPrettyName || Services.SystemService.distroName || "Linux"
                            color: root.theme.textPrimary
                            font.pixelSize: 18
                            font.family: root.font
                            font.weight: Font.DemiBold
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: (Services.SystemService.distroIdLike ? (Services.SystemService.distroIdLike.charAt(0).toUpperCase() + Services.SystemService.distroIdLike.slice(1) + "-based • ") : "") + (Services.SystemService.kernelShort || "Linux")
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ── Hardware Specifications Box ─────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: specsCol.implicitHeight + 16
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1

                        ColumnLayout {
                            id: specsCol
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 6

                            // Model
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Model"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.hardwareModel; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }

                            // Processor
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Processor"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.cpuModel; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }

                            // Graphics
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Graphics"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.gpuModel; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }

                            // Memory
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Memory"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.ramTotal; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }

                            // Kernel
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Kernel"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.kernel; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.04) }

                            // Compositor
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Compositor"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; Layout.preferredWidth: 90 }
                                Text { text: Services.SystemService.compositor; color: root.theme.textPrimary; font.pixelSize: 11; font.family: root.font; font.weight: Font.Medium; Layout.fillWidth: true }
                            }
                        }
                    }

                    // ── Bottom Action Button (Done) ─────────
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        implicitWidth: 90
                        implicitHeight: 28
                        radius: 8
                        color: doneMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Done"
                            color: root.theme.textPrimary
                            font.pixelSize: 12
                            font.family: root.font
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: doneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemService.aboutDialogOpen = false
                        }
                    }
                }
            }
        }
    }
}
