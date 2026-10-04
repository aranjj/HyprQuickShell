import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
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

    IpcHandler {
        target: "notificationcenter"

        function toggle(): void {
            Services.SystemService.toggleNotificationCenter();
        }

        function open(): void {
            Services.SystemService.openNotificationCenter();
        }

        function close(): void {
            Services.SystemService.closeNotificationCenter();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notifWindow
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isOpen: Services.SystemService.notificationCenterOpen
            visible: isOpen || closeAnimTimer.running
            color: "transparent"

            Timer {
                id: closeAnimTimer
                interval: 200
                repeat: false
            }

            onIsOpenChanged: {
                if (!isOpen) closeAnimTimer.restart();
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-notification-center"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: card }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // Click outside to dismiss (transparent backdrop)
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Services.SystemService.notificationCenterOpen = false;
                }
            }

            // ── Floating Bezel Card ─────────
            Rectangle {
                id: card
                width: 382
                readonly property real maxCardHeight: notifWindow.screen.height - (notifWindow.isOpen ? 44 : 26) - 14
                height: Math.min(maxCardHeight, Math.min(620, Math.max(220, (Services.NotificationService.unreadCount === 0 && notifRepeater.count === 0 ? 240 : notifCol.implicitHeight + 80))))
                anchors.top: parent.top
                anchors.topMargin: notifWindow.isOpen ? 44 : 26
                anchors.right: parent.right
                anchors.rightMargin: 14
                scale: notifWindow.isOpen ? 1.0 : 0.94
                opacity: notifWindow.isOpen ? 1.0 : 0.0
                transformOrigin: Item.TopRight

                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Top specular glass highlight
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Services.Aesthetic.cardRadius
                    anchors.rightMargin: Services.Aesthetic.cardRadius
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    z: 10
                }

                // Prevent click dismissal inside card
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // ── Header Bar: Title on Left, DND + Clear All on Right ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Title + Count
                        Row {
                            spacing: 8
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                text: Services.NotificationService.dnd ? "󰂛" : "󰂚"
                                color: root.theme.accent
                                font.pixelSize: 16
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Notifications"
                                color: root.theme.textPrimary
                                font.pixelSize: 14
                                font.family: root.font
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Unread Count Badge
                            Rectangle {
                                visible: Services.NotificationService.unreadCount > 0
                                implicitHeight: 18
                                implicitWidth: Math.max(18, countText.implicitWidth + 8)
                                radius: 9
                                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: Services.NotificationService.unreadCount
                                    color: root.theme.accent
                                    font.pixelSize: 10
                                    font.family: root.font
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // DND Pill
                        Rectangle {
                            id: dndPill
                            implicitHeight: 28
                            implicitWidth: dndPillRow.implicitWidth + 18
                            radius: 14
                            color: Services.NotificationService.dnd ? root.theme.accent : (dndPillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: dndPillRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: Services.NotificationService.dnd ? "󰂛" : "󰂚"
                                    color: Services.NotificationService.dnd ? root.theme.onPrimary : root.theme.textSecondary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: Services.NotificationService.dnd ? "DND On" : "DND"
                                    color: Services.NotificationService.dnd ? root.theme.onPrimary : root.theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: root.font
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: dndPillMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.NotificationService.toggleDnd()
                            }
                        }

                        // Clear All Pill
                        Rectangle {
                            implicitHeight: 28
                            implicitWidth: clearAllText.implicitWidth + 18
                            radius: 14
                            color: clearAllMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                            visible: Services.NotificationService.unreadCount > 0 || notifRepeater.count > 0
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                id: clearAllText
                                anchors.centerIn: parent
                                text: "Clear All"
                                color: root.theme.textSecondary
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: clearAllMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.NotificationService.clearAll()
                            }
                        }
                    }

                    // ── Thin Divider ──
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    // ── Notifications Content Area ──
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Empty State
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: Services.NotificationService.unreadCount === 0 && notifRepeater.count === 0

                            Rectangle {
                                width: 56
                                height: 56
                                radius: 28
                                color: Qt.rgba(1, 1, 1, 0.06)
                                anchors.horizontalCenter: parent.horizontalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰂚"
                                    color: root.theme.textMuted
                                    font.pixelSize: 28
                                    font.family: root.font
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No Notifications"
                                color: root.theme.textPrimary
                                font.pixelSize: 14
                                font.family: root.font
                                font.weight: Font.Bold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "You're completely caught up"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }

                        // Active Notifications List
                        Flickable {
                            id: notifFlickable
                            anchors.fill: parent
                            contentHeight: notifCol.implicitHeight + 10
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            visible: Services.NotificationService.unreadCount > 0 || notifRepeater.count > 0

                            ColumnLayout {
                                id: notifCol
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    id: notifRepeater
                                    model: Services.NotificationService.server.trackedNotifications

                                    Rectangle {
                                        id: notifCard
                                        required property var modelData
                                        required property int index
                                        property bool isExpanded: false
                                        readonly property bool canExpand: bodyText.truncated || isExpanded

                                        Layout.fillWidth: true
                                        implicitHeight: notifCardCol.implicitHeight + 22
                                        radius: 14
                                        color: Services.Aesthetic.innerCardBg
                                        border.color: Services.Aesthetic.innerCardBorder
                                        border.width: 1

                                        ColumnLayout {
                                            id: notifCardCol
                                            width: parent.width - 24
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 11
                                            spacing: 6

                                            // App Header, Timestamp & Dismiss Button
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Item {
                                                    width: 16
                                                    height: 16
                                                    Layout.alignment: Qt.AlignVCenter

                                                    IconImage {
                                                        id: listAppIcon
                                                        anchors.fill: parent
                                                        source: Quickshell.iconPath(notifCard.modelData.appIcon ?? "", true)
                                                        visible: (notifCard.modelData.appIcon ?? "") !== "" && status === Image.Ready
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰂚"
                                                        color: root.theme.accent
                                                        font.pixelSize: 12
                                                        font.family: root.font
                                                        visible: !listAppIcon.visible
                                                    }
                                                }

                                                Text {
                                                    text: (notifCard.modelData.appName && notifCard.modelData.appName.length > 0 ? notifCard.modelData.appName : "NOTIFICATION").toUpperCase()
                                                    color: root.theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.5
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Delivery Time
                                                Text {
                                                    text: Services.NotificationService.getNotificationTime(notifCard.modelData?.id)
                                                    color: root.theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                // Dismiss Button with 28x28px hit area
                                                Item {
                                                    width: 28
                                                    height: 28
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Rectangle {
                                                        width: 18
                                                        height: 18
                                                        radius: 9
                                                        anchors.centerIn: parent
                                                        color: dismissMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)
                                                        Behavior on color { ColorAnimation { duration: 100 } }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "✕"
                                                            color: root.theme.textSecondary
                                                            font.pixelSize: 9
                                                            font.bold: true
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: dismissMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Services.NotificationService.dismiss(notifCard.modelData);
                                                        }
                                                    }
                                                }
                                            }

                                            // Notification Content (Title omitted if empty)
                                            Text {
                                                id: summaryText
                                                Layout.fillWidth: true
                                                text: notifCard.modelData.summary ?? ""
                                                color: root.theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: root.font
                                                font.weight: Font.Bold
                                                wrapMode: Text.Wrap
                                                visible: (notifCard.modelData.summary ?? "").trim().length > 0
                                            }

                                            // Notification Body (Truncated to 3 lines, click to expand up to 12 lines)
                                            Text {
                                                id: bodyText
                                                Layout.fillWidth: true
                                                text: notifCard.modelData.body ?? ""
                                                color: root.theme.textSecondary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                wrapMode: Text.Wrap
                                                maximumLineCount: notifCard.isExpanded ? 12 : 3
                                                elide: Text.ElideRight
                                                visible: (notifCard.modelData.body ?? "").length > 0

                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: notifCard.canExpand
                                                    cursorShape: notifCard.canExpand ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: notifCard.isExpanded = !notifCard.isExpanded
                                                }
                                            }

                                            // Action Buttons (if any)
                                            Row {
                                                spacing: 6
                                                visible: notifCard.modelData.actions && notifCard.modelData.actions.length > 0
                                                Layout.fillWidth: true
                                                Layout.topMargin: 2

                                                Repeater {
                                                    model: notifCard.modelData.actions

                                                    Rectangle {
                                                        id: notifCardActBtn
                                                        required property var modelData
                                                        height: 22
                                                        implicitWidth: notifCardActText.implicitWidth + 14
                                                        radius: 6
                                                        color: notifCardActMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)

                                                        Text {
                                                            id: notifCardActText
                                                            anchors.centerIn: parent
                                                            text: notifCardActBtn.modelData.text
                                                            color: "#ffffff"
                                                            font.pixelSize: 10
                                                            font.family: root.font
                                                            font.weight: Font.Medium
                                                        }

                                                        MouseArea {
                                                            id: notifCardActMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                notifCardActBtn.modelData.invoke();
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

                        // Subtle Bottom Fade Gradient
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 28
                            visible: Services.NotificationService.unreadCount > 0 && notifFlickable.contentHeight > notifFlickable.height
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Services.Aesthetic.cardBg }
                            }
                            z: 5
                        }
                    }
                }
            }
        }
    }
}
