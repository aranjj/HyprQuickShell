import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    // ── Active Navigation Index (0..4) ───────────────
    property int selectedIndex: 0

    // ── IPC Handlers ─────────────────────────────────
    IpcHandler {
        target: "powermenu"
        function toggle(): void { Services.SystemService.togglePowerMenu(); }
        function open(): void { if (!Services.SystemService.powerMenuOpen) Services.SystemService.togglePowerMenu(); }
        function close(): void { if (Services.SystemService.powerMenuOpen) Services.SystemService.togglePowerMenu(); }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { Services.SystemService.togglePowerMenu(); }
        function open(): void { if (!Services.SystemService.powerMenuOpen) Services.SystemService.togglePowerMenu(); }
        function close(): void { if (Services.SystemService.powerMenuOpen) Services.SystemService.togglePowerMenu(); }
    }

    // ── Action Definitions ───────────────────────────
    readonly property var actions: [
        {
            title: "Lock",
            icon: "󰌾",
            key: "L",
            color: root.theme.accent,
            execute: () => {
                root.closeMenu();
                Services.SystemService.lockScreen();
            }
        },
        {
            title: "Sleep",
            icon: "󰤄",
            key: "S",
            color: root.theme.accentMauve,
            execute: () => {
                root.closeMenu();
                Services.SystemService.runCmd("systemctl suspend");
            }
        },
        {
            title: "Logout",
            icon: "󰍃",
            key: "E",
            color: root.theme.accentOrange,
            execute: () => {
                root.closeMenu();
                Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.exit()' || loginctl terminate-session ${XDG_SESSION_ID:-self}");
            }
        },
        {
            title: "Reboot",
            icon: "󰜉",
            key: "R",
            color: root.theme.accentYellow,
            execute: () => {
                root.closeMenu();
                Services.SystemService.runCmd("systemctl reboot");
            }
        },
        {
            title: "Power Off",
            icon: "⏻",
            key: "P",
            color: root.theme.accentRed,
            execute: () => {
                root.closeMenu();
                Services.SystemService.runCmd("systemctl poweroff");
            }
        }
    ]

    function closeMenu() {
        Services.SystemService.powerMenuOpen = false;
        Services.OverlayCoordinator.releaseExclusiveSurface("powerMenu");
    }

    function executeIndex(idx) {
        if (idx >= 0 && idx < actions.length) {
            actions[idx].execute();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: powerMenuWindow
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isOpen: Services.SystemService.powerMenuOpen
            readonly property bool isPrimaryScreen: Quickshell.screens.length > 0 ? (modelData === Quickshell.screens[0]) : true

            visible: isOpen || closeAnimTimer.running
            color: "transparent"
            focusable: true

            Timer {
                id: closeAnimTimer
                interval: 180
                repeat: false
            }

            onIsOpenChanged: {
                if (isOpen) {
                    root.selectedIndex = 0;
                    if (isPrimaryScreen) {
                        Qt.callLater(() => {
                            keyHandler.forceActiveFocus();
                        });
                    }
                } else {
                    closeAnimTimer.restart();
                }
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (powerMenuWindow.isOpen && isPrimaryScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-power-menu"
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region { item: powerCard }

            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }

            // ── Dimmed Backdrop (Click to Dismiss) ────────
            Rectangle {
                anchors.fill: parent
                color: Services.Aesthetic.backdropColor
                opacity: powerMenuWindow.isOpen ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeMenu()
                }
            }

            // ── Keyboard Interaction Handler ──────────────
            Item {
                id: keyHandler
                anchors.fill: parent
                focus: powerMenuWindow.isOpen && powerMenuWindow.isPrimaryScreen

                Keys.onPressed: (event) => {
                    // Esc: dismiss
                    if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        root.closeMenu();
                        return;
                    }

                    // Navigation: Left / Right / Tab / Backtab
                    if (event.key === Qt.Key_Left) {
                        event.accepted = true;
                        root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length;
                        return;
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                        event.accepted = true;
                        root.selectedIndex = (root.selectedIndex + 1) % root.actions.length;
                        return;
                    }
                    if (event.key === Qt.Key_Backtab) {
                        event.accepted = true;
                        root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length;
                        return;
                    }
                    if (event.key === Qt.Key_Home) {
                        event.accepted = true;
                        root.selectedIndex = 0;
                        return;
                    }
                    if (event.key === Qt.Key_End) {
                        event.accepted = true;
                        root.selectedIndex = root.actions.length - 1;
                        return;
                    }

                    // Execute selected: Enter or Space
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true;
                        root.executeIndex(root.selectedIndex);
                        return;
                    }

                    // Hotkeys: L / 1 (Lock)
                    if (event.key === Qt.Key_L || event.key === Qt.Key_1) {
                        event.accepted = true;
                        root.executeIndex(0);
                        return;
                    }

                    // Hotkeys: S / 2 (Sleep)
                    if (event.key === Qt.Key_S || event.key === Qt.Key_2) {
                        event.accepted = true;
                        root.executeIndex(1);
                        return;
                    }

                    // Hotkeys: E / 3 (Logout)
                    if (event.key === Qt.Key_E || event.key === Qt.Key_3) {
                        event.accepted = true;
                        root.executeIndex(2);
                        return;
                    }

                    // Hotkeys: R / 4 (Reboot)
                    if (event.key === Qt.Key_R || event.key === Qt.Key_4) {
                        event.accepted = true;
                        root.executeIndex(3);
                        return;
                    }

                    // Hotkeys: P / 5 (Power Off)
                    if (event.key === Qt.Key_P || event.key === Qt.Key_5) {
                        event.accepted = true;
                        root.executeIndex(4);
                        return;
                    }
                }
            }

            // ── Clean Power Menu Card ─────────────────────
            Rectangle {
                id: powerCard
                anchors.centerIn: parent
                anchors.verticalCenterOffset: powerMenuWindow.isOpen ? 0 : -14
                scale: powerMenuWindow.isOpen ? 1.0 : 0.90
                opacity: powerMenuWindow.isOpen ? 1.0 : 0.0
                width: 500
                height: 184
                radius: Services.Aesthetic.cardRadius
                color: Services.Aesthetic.cardBg
                border.color: Services.Aesthetic.cardBorder
                border.width: Services.Aesthetic.borderWidth
                clip: true

                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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

                // Stop dismissal click from propagating
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // Title Header Row
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Power Options"
                            color: root.theme.textPrimary
                            font.pixelSize: 15
                            font.family: root.font
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeMenu()
                            }
                        }
                    }

                    // Action Buttons Row (5 Clean Tiles)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: root.actions

                            Rectangle {
                                id: actionBtn
                                Layout.fillWidth: true
                                implicitHeight: 88
                                radius: 14

                                readonly property bool isSelected: root.selectedIndex === index
                                readonly property bool isHovered: btnMouse.containsMouse
                                readonly property bool isPowerOff: index === 4

                                color: isSelected
                                    ? (isPowerOff ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.22) : root.theme.pillHover)
                                    : (isHovered ? root.theme.pillHover : root.theme.pillBg)

                                border.color: isSelected
                                    ? modelData.color
                                    : (isHovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: isSelected ? 1.5 : 1

                                scale: isSelected ? 1.04 : (isHovered ? 1.02 : 1.0)

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    // Action Icon
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        color: modelData.color
                                        font.pixelSize: 22
                                        font.family: root.font
                                        scale: isSelected ? 1.08 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                    }

                                    // Action Label
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.title
                                        color: isSelected ? root.theme.textPrimary : root.theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: isSelected ? Font.DemiBold : Font.Medium
                                        renderType: Text.NativeRendering
                                    }

                                    // Keyboard Shortcut Hint Pill
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 22
                                        height: 16
                                        radius: 4
                                        color: isSelected ? modelData.color : Qt.rgba(1, 1, 1, 0.06)
                                        border.color: isSelected ? Qt.lighter(modelData.color, 1.2) : Qt.rgba(1, 1, 1, 0.10)
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.key
                                            color: isSelected ? "#090d16" : root.theme.textMuted
                                            font.pixelSize: 9
                                            font.family: root.font
                                            font.weight: Font.Bold
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }

                                MouseArea {
                                    id: btnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIndex = index
                                    onClicked: root.executeIndex(index)
                                }
                            }
                        }
                    }

                    // Bottom Navigation Hint Footer
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2

                        Text {
                            text: "󰌌"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                        }

                        Text {
                            text: "Use ← → or [L, S, E, R, P] • Enter to select • Esc to exit"
                            color: root.theme.textMuted
                            font.pixelSize: 10
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
