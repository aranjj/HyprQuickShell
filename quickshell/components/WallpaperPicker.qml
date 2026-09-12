import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../bar" as Bar
import "../services" as Services

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"
    property int selectedIndex: 0

    function stepIndex(delta) {
        const list = Services.WallpaperService.wallpapers;
        if (!list || list.length === 0) return;
        let next = (root.selectedIndex + delta) % list.length;
        if (next < 0) next += list.length;
        setIndex(next);
    }

    function setIndex(idx) {
        const list = Services.WallpaperService.wallpapers;
        if (!list || list.length === 0) return;
        root.selectedIndex = Math.max(0, Math.min(idx, list.length - 1));
        carouselList.currentIndex = root.selectedIndex;
        carouselList.positionViewAtIndex(root.selectedIndex, ListView.Center);
    }

    function confirmSelection() {
        const list = Services.WallpaperService.wallpapers;
        if (list && list[root.selectedIndex]) {
            Services.WallpaperService.setWallpaper(list[root.selectedIndex]);
        }
        Services.WallpaperService.closePicker();
    }

    function randomSelection() {
        const list = Services.WallpaperService.wallpapers;
        if (!list || list.length === 0) return;
        const rand = Math.floor(Math.random() * list.length);
        setIndex(rand);
    }

    PanelWindow {
        id: pickerWin
        visible: Services.WallpaperService.pickerOpen
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: pickerWin.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-wallpaper-picker"
        exclusionMode: ExclusionMode.Ignore

        BackgroundEffect.blurRegion: Region { item: mainModal }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: {
            if (visible) {
                const list = Services.WallpaperService.wallpapers;
                const curr = Services.WallpaperService.currentWallpaper.replace(/^file:\/\//, "");
                let idx = list.indexOf(curr);
                if (idx < 0) idx = 0;
                root.selectedIndex = idx;
                carouselList.currentIndex = idx;
                Qt.callLater(() => {
                    carouselList.positionViewAtIndex(idx, ListView.Center);
                    keyReceiver.forceActiveFocus();
                });
            }
        }

        // Dimmed backdrop (click to dismiss)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.60)

            MouseArea {
                anchors.fill: parent
                onClicked: Services.WallpaperService.closePicker()
            }
        }

        // Keyboard Receiver
        Item {
            id: keyReceiver
            anchors.fill: parent
            focus: true

            Keys.onPressed: (event) => {
                const total = Services.WallpaperService.wallpapers.length;
                if (total === 0) return;

                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    Services.WallpaperService.closePicker();
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                    event.accepted = true;
                    root.stepIndex(-1);
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                    event.accepted = true;
                    root.stepIndex(1);
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
                    event.accepted = true;
                    root.stepIndex(-5);
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
                    event.accepted = true;
                    root.stepIndex(5);
                } else if (event.key === Qt.Key_Home) {
                    event.accepted = true;
                    root.setIndex(0);
                } else if (event.key === Qt.Key_End) {
                    event.accepted = true;
                    root.setIndex(total - 1);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    event.accepted = true;
                    root.confirmSelection();
                } else if (event.key === Qt.Key_R) {
                    event.accepted = true;
                    root.randomSelection();
                }
            }
        }

        // Main Floating Modal Container
        Rectangle {
            id: mainModal
            anchors.centerIn: parent
            width: Math.min(pickerWin.width * 0.88, 1040)
            height: 540
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

            // Prevent click propagation
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                // ── Header Bar ──────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Icon + Title
                    RowLayout {
                        spacing: 8
                        Text {
                            text: "󰸉"
                            color: root.theme.accent
                            font.pixelSize: 18
                            font.family: root.font
                        }

                        Text {
                            text: "Wallpapers"
                            color: root.theme.textPrimary
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            font.family: root.font
                        }
                    }

                    // Counter Pill
                    Rectangle {
                        height: 24
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Layout.preferredWidth: counterText.implicitWidth + 16

                        Text {
                            id: counterText
                            anchors.centerIn: parent
                            text: (Services.WallpaperService.wallpapers.length > 0)
                                ? (root.selectedIndex + 1) + " of " + Services.WallpaperService.wallpapers.length
                                : "Loading..."
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.family: root.font
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Keyboard Navigation Hints (top right)
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            height: 24
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            Layout.preferredWidth: hintArrows.implicitWidth + 10
                            RowLayout {
                                id: hintArrows
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "← →"; color: root.theme.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font }
                                Text { text: "Navigate"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }
                        }

                        Rectangle {
                            height: 24
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            Layout.preferredWidth: hintEnter.implicitWidth + 10
                            RowLayout {
                                id: hintEnter
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "↵ Enter"; color: "#30d158"; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font }
                                Text { text: "Set"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }
                        }

                        Rectangle {
                            height: 24
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            Layout.preferredWidth: hintEsc.implicitWidth + 10
                            RowLayout {
                                id: hintEsc
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "Esc"; color: root.theme.textMuted; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font }
                                Text { text: "Close"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.WallpaperService.closePicker()
                        }
                    }
                }

                // ── Carousel Section ────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: carouselList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 16
                        highlightFollowsCurrentItem: true
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: (width - 400) / 2
                        preferredHighlightEnd: (width + 400) / 2
                        snapMode: ListView.SnapToItem
                        model: Services.WallpaperService.wallpapers

                        delegate: Item {
                            required property string modelData
                            required property int index
                            width: 400
                            height: carouselList.height

                            readonly property bool isSelected: index === root.selectedIndex
                            readonly property bool isCurrentlyActive: {
                                const clean = Services.WallpaperService.currentWallpaper.replace(/^file:\/\//, "");
                                return clean === modelData;
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: isSelected ? 390 : 310
                                height: isSelected ? 230 : 185
                                radius: 14
                                clip: true
                                color: Qt.rgba(0, 0, 0, 0.3)
                                border.color: isSelected ? root.theme.accent : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.08))
                                border.width: isSelected ? 2 : 1
                                opacity: isSelected ? 1.0 : (cardMouse.containsMouse ? 0.75 : 0.45)

                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 520
                                    sourceSize.height: 300
                                }

                                // Active system wallpaper badge
                                Rectangle {
                                    visible: isCurrentlyActive
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    height: 20
                                    radius: 10
                                    color: root.theme.accentGreen
                                    width: activeBadgeRow.implicitWidth + 12

                                    RowLayout {
                                        id: activeBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            text: "ACTIVE"
                                            color: "#ffffff"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.family: root.font
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setIndex(index);
                                    }
                                    onDoubleClicked: {
                                        root.setIndex(index);
                                        root.confirmSelection();
                                    }
                                }
                            }
                        }
                    }

                    // Left Arrow Overlay Button
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        color: leftBtnMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: leftBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stepIndex(-1)
                        }
                    }

                    // Right Arrow Overlay Button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        color: rightBtnMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: rightBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stepIndex(1)
                        }
                    }
                }

                // ── Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Shell Aesthetic Preset Selector ─────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "Shell Aesthetic:"
                        color: root.theme.textSecondary
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.family: root.font
                    }

                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: Services.Aesthetic.presets

                            Rectangle {
                                required property var modelData
                                height: 28
                                radius: 8
                                color: Services.Aesthetic.preset === modelData.id
                                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22)
                                    : (optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04))
                                border.color: Services.Aesthetic.preset === modelData.id
                                    ? root.theme.accent
                                    : Qt.rgba(1, 1, 1, 0.09)
                                border.width: 1
                                Layout.preferredWidth: optRow.implicitWidth + 16

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    id: optRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: modelData.icon
                                        color: Services.Aesthetic.preset === modelData.id ? root.theme.accent : root.theme.textMuted
                                        font.pixelSize: 12
                                        font.family: root.font
                                    }

                                    Text {
                                        text: modelData.name
                                        color: Services.Aesthetic.preset === modelData.id ? "#ffffff" : root.theme.textSecondary
                                        font.pixelSize: 11
                                        font.weight: Services.Aesthetic.preset === modelData.id ? Font.DemiBold : Font.Normal
                                        font.family: root.font
                                    }
                                }

                                MouseArea {
                                    id: optMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Aesthetic.setPreset(modelData.id)
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Current Preset Description
                    Text {
                        text: {
                            for (let i = 0; i < Services.Aesthetic.presets.length; i++) {
                                if (Services.Aesthetic.presets[i].id === Services.Aesthetic.preset) {
                                    return Services.Aesthetic.presets[i].desc;
                                }
                            }
                            return "";
                        }
                        color: root.theme.textMuted
                        font.pixelSize: 11
                        font.family: root.font
                    }
                }

                // ── Footer Bar ──────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Selected Wallpaper Info
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: (Services.WallpaperService.wallpapers.length > 0 && Services.WallpaperService.wallpapers[root.selectedIndex])
                                ? Services.WallpaperService.extractName(Services.WallpaperService.wallpapers[root.selectedIndex])
                                : "Select a Wallpaper"
                            color: root.theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: root.font
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: (Services.WallpaperService.wallpapers.length > 0 && Services.WallpaperService.wallpapers[root.selectedIndex])
                                ? Services.WallpaperService.wallpapers[root.selectedIndex].split("/").pop()
                                : ""
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    // Random Button
                    Rectangle {
                        height: 34
                        radius: 8
                        color: randBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        Layout.preferredWidth: randRow.implicitWidth + 20
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: randRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰘚"; color: "#ff9f0a"; font.pixelSize: 13; font.family: root.font }
                            Text { text: "Random (R)"; color: root.theme.textPrimary; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.font }
                        }

                        MouseArea {
                            id: randBtnM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.randomSelection()
                        }
                    }

                    // Cancel Button
                    Rectangle {
                        height: 34
                        radius: 8
                        color: cancelBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        Layout.preferredWidth: 72
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.theme.textSecondary
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            font.family: root.font
                        }

                        MouseArea {
                            id: cancelBtnM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.WallpaperService.closePicker()
                        }
                    }

                    // Apply Button (Primary)
                    Rectangle {
                        height: 34
                        radius: 8
                        color: applyBtnM.containsMouse ? Qt.darker(root.theme.accent, 1.15) : root.theme.accent
                        Layout.preferredWidth: applyRow.implicitWidth + 24
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: applyRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰄬"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Bold; font.family: root.font }
                            Text { text: "Set Wallpaper"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: root.font }
                        }

                        MouseArea {
                            id: applyBtnM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmSelection()
                        }
                    }
                }
            }
        }
    }
}
