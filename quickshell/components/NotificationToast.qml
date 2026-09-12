import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
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
            id: toastWin
            required property ShellScreen modelData
            screen: modelData

            visible: Services.NotificationService.popups.length > 0
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-notification-popups"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: toastCol }

            anchors {
                top: true
                right: true
            }

            margins {
                top: 48
                right: 16
            }

            implicitWidth: 350
            implicitHeight: toastCol.implicitHeight

            Column {
                id: toastCol
                width: 350
                spacing: 10

                Repeater {
                    model: Services.NotificationService.popups

                    Rectangle {
                        id: bannerCard
                        required property var modelData
                        required property int index

                        width: 350
                        implicitHeight: contentCol.implicitHeight + 24
                        radius: 16
                        color: Qt.rgba(0.12, 0.12, 0.18, 0.78)
                        border.color: Qt.rgba(1, 1, 1, 0.16)
                        border.width: 1
                        clip: true

                        // Slide & Fade entrance
                        opacity: 1
                        Behavior on opacity { NumberAnimation { duration: 180 } }

                        // Auto-dismiss timer (paused while hovered)
                        Timer {
                            id: dismissTimer
                            interval: 5000
                            running: !bannerMouse.containsMouse
                            repeat: false
                            onTriggered: {
                                Services.NotificationService.removePopup(bannerCard.modelData.id);
                            }
                        }

                        // Background hover & click
                        MouseArea {
                            id: bannerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const notif = bannerCard.modelData.notif;
                                if (notif && notif.actions && notif.actions.length > 0) {
                                    notif.actions[0].invoke();
                                }
                                Services.NotificationService.removePopup(bannerCard.modelData.id);
                            }
                        }

                        ColumnLayout {
                            id: contentCol
                            width: parent.width - 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            spacing: 8

                            // ── Header: Icon + App Name + Time + Close Button ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // App Icon
                                Item {
                                    width: 18
                                    height: 18
                                    Layout.alignment: Qt.AlignVCenter

                                    IconImage {
                                        id: appIconImg
                                        anchors.fill: parent
                                        source: Quickshell.iconPath(bannerCard.modelData.appIcon ?? "", true)
                                        visible: (bannerCard.modelData.appIcon ?? "") !== "" && status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰂚"
                                        color: root.theme.accent
                                        font.pixelSize: 13
                                        font.family: root.font
                                        visible: !appIconImg.visible
                                    }
                                }

                                // App Name
                                Text {
                                    text: bannerCard.modelData.appName.toUpperCase()
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.5
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Item { Layout.fillWidth: true }

                                // Time
                                Text {
                                    text: bannerCard.modelData.timeStr
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Close Button
                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: root.theme.textSecondary
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Services.NotificationService.removePopup(bannerCard.modelData.id);
                                        }
                                    }
                                }
                            }

                            // ── Body Area: Title + Body + Optional Image ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: bannerCard.modelData.summary
                                        color: root.theme.textPrimary
                                        font.pixelSize: 13
                                        font.family: root.font
                                        font.weight: Font.Bold
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: bannerCard.modelData.body
                                        color: Qt.rgba(0.90, 0.90, 0.95, 0.85)
                                        font.pixelSize: 12
                                        font.family: root.font
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        visible: bannerCard.modelData.body.length > 0
                                    }
                                }

                                // Optional Notification Image
                                Image {
                                    source: bannerCard.modelData.image ?? ""
                                    visible: (bannerCard.modelData.image ?? "") !== ""
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44
                                    fillMode: Image.PreserveAspectCrop
                                    layer.enabled: true
                                }
                            }

                            // ── Action Buttons Row ──
                            Row {
                                spacing: 6
                                visible: bannerCard.modelData.notif && bannerCard.modelData.notif.actions && bannerCard.modelData.notif.actions.length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 2

                                Repeater {
                                    model: bannerCard.modelData.notif ? bannerCard.modelData.notif.actions : []

                                    Rectangle {
                                        id: actBtn
                                        required property var modelData
                                        height: 24
                                        implicitWidth: actText.implicitWidth + 16
                                        radius: 6
                                        color: actMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)

                                        Text {
                                            id: actText
                                            anchors.centerIn: parent
                                            text: actBtn.modelData.text
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.family: root.font
                                            font.weight: Font.Medium
                                        }

                                        MouseArea {
                                            id: actMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                actBtn.modelData.invoke();
                                                Services.NotificationService.removePopup(bannerCard.modelData.id);
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
