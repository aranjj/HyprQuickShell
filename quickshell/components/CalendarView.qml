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

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() // 0-11

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function prevMonth() {
        if (viewMonth === 0) {
            viewMonth = 11;
            viewYear--;
        } else {
            viewMonth--;
        }
    }

    function nextMonth() {
        if (viewMonth === 11) {
            viewMonth = 0;
            viewYear++;
        } else {
            viewMonth++;
        }
    }

    function resetToToday() {
        const d = new Date();
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
    }

    function getMonthCells(year, month) {
        const firstDayOfWeek = new Date(year, month, 1).getDay(); // 0 = Sun
        const startOffset = (firstDayOfWeek + 6) % 7; // Monday = 0
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrevMonth = new Date(year, month, 0).getDate();

        const cells = [];
        // Previous month padding
        for (let i = startOffset - 1; i >= 0; i--) {
            cells.push({ day: daysInPrevMonth - i, isCurrentMonth: false, isToday: false });
        }
        // Current month
        const today = new Date();
        for (let d = 1; d <= daysInMonth; d++) {
            const isToday = (today.getFullYear() === year && today.getMonth() === month && today.getDate() === d);
            cells.push({ day: d, isCurrentMonth: true, isToday: isToday });
        }
        // Next month padding to reach 35 or 42 cells
        const total = cells.length <= 35 ? 35 : 42;
        const remaining = total - cells.length;
        for (let d = 1; d <= remaining; d++) {
            cells.push({ day: d, isCurrentMonth: false, isToday: false });
        }
        return cells;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: calWindow
            required property ShellScreen modelData
            screen: modelData

            visible: Services.ClockService.calendarOpen
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-calendar"
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // Click backdrop to dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: Services.ClockService.calendarOpen = false
            }

            // Floating Calendar Card
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 46
                anchors.right: parent.right
                anchors.rightMargin: 12

                width: 320
                height: 380
                radius: 18
                color: Qt.rgba(0.11, 0.11, 0.16, 0.95)
                border.color: Qt.rgba(1, 1, 1, 0.13)
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ── Header: Time & Full Date ────────────
                    RowLayout {
                        Layout.fillWidth: true

                        Column {
                            spacing: 2
                            Text {
                                text: Services.ClockService.time
                                color: root.theme.textPrimary
                                font.pixelSize: 26
                                font.family: root.font
                                font.weight: Font.Bold
                            }
                            Text {
                                text: Services.ClockService.date
                                color: root.theme.accent
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.Medium
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Reset to today button
                        Rectangle {
                            width: 64
                            height: 26
                            radius: 8
                            color: todayBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: "Today"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: todayBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.resetToToday()
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // ── Month Navigator ─────────────────────
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: root.monthNames[root.viewMonth] + " " + root.viewYear
                            color: root.theme.textPrimary
                            font.pixelSize: 14
                            font.family: root.font
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Previous Month button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: prevBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: "#ffffff"
                                font.pixelSize: 16
                                font.family: root.font
                            }
                            MouseArea {
                                id: prevBtnM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.prevMonth()
                            }
                        }

                        // Next Month button
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: nextBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "›"
                                color: "#ffffff"
                                font.pixelSize: 16
                                font.family: root.font
                            }
                            MouseArea {
                                id: nextBtnM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.nextMonth()
                            }
                        }
                    }

                    // ── Days of Week Header ─────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

                            Text {
                                required property string modelData
                                text: modelData
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                                font.weight: Font.DemiBold
                                Layout.preferredWidth: 288 / 7
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // ── Days Grid ───────────────────────────
                    GridLayout {
                        id: dayGrid
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: 4
                        columnSpacing: 0

                        Repeater {
                            model: root.getMonthCells(root.viewYear, root.viewMonth)

                            Item {
                                required property var modelData
                                Layout.preferredWidth: 288 / 7
                                Layout.preferredHeight: 30

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: modelData.isToday ? root.theme.accent
                                         : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12)
                                         : "transparent"

                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        color: modelData.isToday ? "#ffffff"
                                             : (modelData.isCurrentMonth ? root.theme.textPrimary : root.theme.textMuted)
                                        font.pixelSize: 12
                                        font.family: root.font
                                        font.weight: modelData.isToday ? Font.Bold : Font.Normal
                                    }

                                    MouseArea {
                                        id: cellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
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
