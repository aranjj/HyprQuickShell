import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import "../bar" as Bar
import "../services" as Services

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"
    property int selectedIndex: 0
    property bool isFolderInputOpen: false

    IpcHandler {
        target: "wallpaperpicker"
        function folder(): void { root.openFolderInput(); }
        function closeFolder(): void { root.closeFolderInput(); }
    }

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

    function openFolderInput() {
        folderTextInput.text = Services.WallpaperService.wallpapersDir;
        root.isFolderInputOpen = true;
        Qt.callLater(() => {
            folderTextInput.forceActiveFocus();
            folderTextInput.selectAll();
        });
    }

    function closeFolderInput() {
        root.isFolderInputOpen = false;
        Qt.callLater(() => {
            keyReceiver.forceActiveFocus();
        });
    }

    function applyFolderInput() {
        if (folderTextInput.text && folderTextInput.text.trim().length > 0) {
            Services.WallpaperService.setWallpapersDir(folderTextInput.text.trim());
        }
        closeFolderInput();
    }

    property bool isOpen: Services.WallpaperService.pickerOpen
    onIsOpenChanged: {
        if (!isOpen) {
            root.isFolderInputOpen = false;
            closeAnimTimer.restart();
        } else {
            closeAnimTimer.stop();
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 180
        repeat: false
    }

    PanelWindow {
        id: pickerWin
        visible: root.isOpen || closeAnimTimer.running
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (root.isOpen || closeAnimTimer.running) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
            if (visible && root.isOpen) {
                root.isFolderInputOpen = false;
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
            color: Services.Aesthetic.backdropColor
            opacity: root.isOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.isFolderInputOpen) {
                        root.closeFolderInput();
                    } else {
                        Services.WallpaperService.closePicker();
                    }
                }
            }
        }

        // Keyboard Receiver
        Item {
            id: keyReceiver
            anchors.fill: parent
            focus: true
            enabled: !root.isFolderInputOpen

            Keys.onPressed: (event) => {
                const total = Services.WallpaperService.wallpapers.length;

                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    Services.WallpaperService.closePicker();
                } else if (event.key === Qt.Key_F || (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier))) {
                    event.accepted = true;
                    root.openFolderInput();
                } else if (total > 0) {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
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
        }

        // Main Floating Modal Container
        Rectangle {
            id: mainModal
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.isOpen ? 0 : -16
            scale: root.isOpen ? 1.0 : 0.92
            opacity: root.isOpen ? 1.0 : 0.0
            transformOrigin: Item.Center

            Behavior on scale {
                NumberAnimation {
                    duration: root.isOpen ? 220 : 160
                    easing.type: root.isOpen ? Easing.OutBack : Easing.InQuad
                    easing.overshoot: 1.05
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on anchors.verticalCenterOffset {
                NumberAnimation {
                    duration: root.isOpen ? 220 : 160
                    easing.type: root.isOpen ? Easing.OutCubic : Easing.InQuad
                }
            }

            width: Math.min(pickerWin.width * 0.88, 1040)
            height: 540
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

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
                            renderType: Text.NativeRendering
                        }

                        Text {
                            text: "Wallpapers"
                            color: root.theme.textPrimary
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }
                    }

                    // Counter Pill
                    Rectangle {
                        height: 24
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        Layout.preferredWidth: counterText.implicitWidth + 16

                        Text {
                            id: counterText
                            anchors.centerIn: parent
                            text: (Services.WallpaperService.wallpapers.length > 0)
                                ? (root.selectedIndex + 1) + " of " + Services.WallpaperService.wallpapers.length
                                : "0 wallpapers"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }
                    }

                    // Folder Selector Pill
                    Rectangle {
                        height: 26
                        radius: 13
                        color: folderMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                        border.color: (folderMouse.containsMouse || root.isFolderInputOpen) ? root.theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        Layout.preferredWidth: folderRow.implicitWidth + 20
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: folderRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰉋"
                                color: root.theme.accent
                                font.pixelSize: 13
                                font.family: root.font
                            }

                            Text {
                                text: {
                                    const dir = Services.WallpaperService.wallpapersDir;
                                    const parts = dir.split("/");
                                    return parts[parts.length - 1] || "Wallpapers";
                                }
                                color: root.theme.textPrimary
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "▾"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: folderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.isFolderInputOpen) root.closeFolderInput();
                                else root.openFolderInput();
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Keyboard Navigation Hints (top right)
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            height: 22
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Layout.preferredWidth: hintFolder.implicitWidth + 12
                            RowLayout {
                                id: hintFolder
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "F"; color: root.theme.accent; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font; renderType: Text.NativeRendering }
                                Text { text: "Folder"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; renderType: Text.NativeRendering }
                            }
                        }

                        Rectangle {
                            height: 22
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Layout.preferredWidth: hintArrows.implicitWidth + 12
                            RowLayout {
                                id: hintArrows
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "← →"; color: root.theme.textSecondary; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font; renderType: Text.NativeRendering }
                                Text { text: "Navigate"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; renderType: Text.NativeRendering }
                            }
                        }

                        Rectangle {
                            height: 22
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Layout.preferredWidth: hintEnter.implicitWidth + 12
                            RowLayout {
                                id: hintEnter
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "↵ Enter"; color: "#30d158"; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font; renderType: Text.NativeRendering }
                                Text { text: "Set"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; renderType: Text.NativeRendering }
                            }
                        }

                        Rectangle {
                            height: 22
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Layout.preferredWidth: hintEsc.implicitWidth + 12
                            RowLayout {
                                id: hintEsc
                                anchors.centerIn: parent
                                spacing: 4
                                Text { text: "Esc"; color: root.theme.textMuted; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.font; renderType: Text.NativeRendering }
                                Text { text: "Close"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; renderType: Text.NativeRendering }
                            }
                        }
                    }

                    // Close Button
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
                            onClicked: Services.WallpaperService.closePicker()
                        }
                    }
                }

                // ── Carousel Section (OR Empty State) ───────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ── Empty State Card ────────────────────────────────
                    Item {
                        anchors.fill: parent
                        visible: Services.WallpaperService.wallpapers.length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 68
                                height: 68
                                radius: 34
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰸉"
                                    color: root.theme.accent
                                    font.pixelSize: 32
                                    font.family: root.font
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "No Wallpapers Found"
                                color: root.theme.textPrimary
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 460
                                text: "No supported images (.jpg, .jpeg, .png, .webp) found in:\n" + Services.WallpaperService.wallpapersDir
                                color: root.theme.textMuted
                                font.pixelSize: 12
                                font.family: root.font
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                renderType: Text.NativeRendering
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 8
                                spacing: 10

                                // Choose Folder Button
                                Rectangle {
                                    height: 34
                                    radius: 10
                                    color: chooseBtnM.containsMouse ? root.theme.pillHover : root.theme.pillBg
                                    border.color: root.theme.accent
                                    border.width: 1
                                    Layout.preferredWidth: chooseRow.implicitWidth + 24
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    RowLayout {
                                        id: chooseRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰉋"; color: root.theme.accent; font.pixelSize: 13; font.family: root.font }
                                        Text { text: "Enter Folder Path (F)"; color: root.theme.textPrimary; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: chooseBtnM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openFolderInput()
                                    }
                                }

                                // Reset to Default Button
                                Rectangle {
                                    visible: Services.WallpaperService.wallpapersDir !== Services.WallpaperService.defaultDir
                                    height: 34
                                    radius: 10
                                    color: resetBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1
                                    Layout.preferredWidth: resetRow.implicitWidth + 20
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    RowLayout {
                                        id: resetRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰑐"; color: root.theme.textMuted; font.pixelSize: 12; font.family: root.font }
                                        Text { text: "Default Folder"; color: root.theme.textSecondary; font.pixelSize: 12; font.family: root.font }
                                    }

                                    MouseArea {
                                        id: resetBtnM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.WallpaperService.resetWallpapersDir()
                                    }
                                }
                            }
                        }
                    }

                    // ── Active Carousel List ────────────────────────────
                    ListView {
                        id: carouselList
                        anchors.fill: parent
                        visible: Services.WallpaperService.wallpapers.length > 0
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

                            // ── Card Frame Container ──
                            Rectangle {
                                id: cardFrame
                                anchors.centerIn: parent
                                width: isSelected ? 390 : 310
                                height: isSelected ? 230 : 185
                                radius: 16
                                color: Qt.rgba(0, 0, 0, 0.5)
                                opacity: isSelected ? 1.0 : (cardMouse.containsMouse ? 0.75 : 0.45)
                                clip: true

                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                // 1. Rounded Mask for cropping Image
                                Rectangle {
                                    id: imgMask
                                    anchors.fill: parent
                                    radius: cardFrame.radius
                                    color: "#ffffff"
                                    visible: false
                                    layer.enabled: true
                                }

                                // 2. Source Image (hidden; feeds MultiEffect)
                                Image {
                                    id: wallImg
                                    anchors.fill: parent
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    visible: false
                                    sourceSize.width: 520
                                    sourceSize.height: 300
                                }

                                // 3. Perfectly Cropped Image
                                MultiEffect {
                                    anchors.fill: parent
                                    source: wallImg
                                    maskEnabled: true
                                    maskSource: imgMask
                                    visible: wallImg.status === Image.Ready
                                }

                                // 4. Crisp Overlay Border ON TOP of the image
                                Rectangle {
                                    anchors.fill: parent
                                    radius: cardFrame.radius
                                    color: "transparent"
                                    border.color: isSelected ? root.theme.accent : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.10))
                                    border.width: isSelected ? 3 : 1
                                    z: 10
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    Behavior on border.width { NumberAnimation { duration: 120 } }
                                }

                                // 5. Active System Wallpaper Badge
                                Rectangle {
                                    visible: isCurrentlyActive
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 10
                                    height: 22
                                    radius: 11
                                    color: root.theme.accentGreen
                                    width: activeBadgeRow.implicitWidth + 14
                                    z: 20

                                    RowLayout {
                                        id: activeBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            renderType: Text.NativeRendering
                                        }
                                        Text {
                                            text: "ACTIVE"
                                            color: "#ffffff"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.family: root.font
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setIndex(index)
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
                        visible: Services.WallpaperService.wallpapers.length > 0
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
                            renderType: Text.NativeRendering
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
                        visible: Services.WallpaperService.wallpapers.length > 0
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
                            renderType: Text.NativeRendering
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
                        renderType: Text.NativeRendering
                    }

                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: Services.Aesthetic.presets

                            Rectangle {
                                required property var modelData
                                height: 26
                                radius: 13
                                color: Services.Aesthetic.preset === modelData.id
                                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)
                                    : (optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                border.color: Services.Aesthetic.preset === modelData.id
                                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45)
                                    : (optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                Layout.preferredWidth: optRow.implicitWidth + 18

                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    id: optRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        text: modelData.icon
                                        color: Services.Aesthetic.preset === modelData.id ? root.theme.accent : root.theme.textMuted
                                        font.pixelSize: 11
                                        font.family: root.font
                                        renderType: Text.NativeRendering
                                    }

                                    Text {
                                        text: modelData.name
                                        color: Services.Aesthetic.preset === modelData.id ? root.theme.accent : (optMouse.containsMouse ? root.theme.textPrimary : root.theme.textSecondary)
                                        font.pixelSize: 11
                                        font.weight: Services.Aesthetic.preset === modelData.id ? Font.DemiBold : Font.Normal
                                        font.family: root.font
                                        renderType: Text.NativeRendering
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
                                    return "• " + Services.Aesthetic.presets[i].desc;
                                }
                            }
                            return "";
                        }
                        color: root.theme.textMuted
                        font.pixelSize: 11
                        font.family: root.font
                        renderType: Text.NativeRendering
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
                                : (Services.WallpaperService.wallpapers.length > 0 ? "Select a Wallpaper" : "No Wallpapers Available")
                            color: root.theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: root.font
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            renderType: Text.NativeRendering
                        }

                        Text {
                            text: (Services.WallpaperService.wallpapers.length > 0 && Services.WallpaperService.wallpapers[root.selectedIndex])
                                ? Services.WallpaperService.wallpapers[root.selectedIndex].split("/").pop()
                                : Services.WallpaperService.wallpapersDir
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                            renderType: Text.NativeRendering
                        }
                    }

                    // Random Button
                    Rectangle {
                        height: 32
                        radius: 8
                        color: randBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        enabled: Services.WallpaperService.wallpapers.length > 0
                        opacity: enabled ? 1.0 : 0.40
                        Layout.preferredWidth: randRow.implicitWidth + 20
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: randRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰘚"; color: "#ff9f0a"; font.pixelSize: 13; font.family: root.font; renderType: Text.NativeRendering }
                            Text { text: "Random (R)"; color: root.theme.textPrimary; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.font; renderType: Text.NativeRendering }
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
                        height: 32
                        radius: 8
                        color: cancelBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
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
                            renderType: Text.NativeRendering
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
                        height: 32
                        radius: 8
                        enabled: Services.WallpaperService.wallpapers.length > 0
                        opacity: enabled ? 1.0 : 0.40
                        color: applyBtnM.pressed ? Qt.darker(root.theme.accent, 1.25) : (applyBtnM.containsMouse ? Qt.darker(root.theme.accent, 1.15) : root.theme.accent)
                        Layout.preferredWidth: applyRow.implicitWidth + 24
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: applyRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰄬"; color: "#090d16"; font.pixelSize: 13; font.weight: Font.Bold; font.family: root.font; renderType: Text.NativeRendering }
                            Text { text: "Set Wallpaper"; color: "#090d16"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: root.font; renderType: Text.NativeRendering }
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

            // ── Inline Folder Input Modal Overlay ───────────────────────
            Item {
                anchors.fill: parent
                visible: root.isFolderInputOpen
                z: 100

                // Scrim backdrop
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.50)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.closeFolderInput()
                    }
                }

                // Centered Dialog
                Rectangle {
                    anchors.centerIn: parent
                    width: 520
                    height: 190
                    radius: 18
                    color: Services.Aesthetic.preset === "solid" ? Services.Aesthetic.cardBg : Qt.rgba(0.08, 0.08, 0.10, 0.96)
                    border.color: Services.Aesthetic.cardBorder
                    border.width: 1
                    clip: true

                    // Top specular highlight
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "󰉋"; color: root.theme.accent; font.pixelSize: 15; font.family: root.font }
                            Text { text: "Set Wallpaper Folder Path"; color: root.theme.textPrimary; font.pixelSize: 14; font.weight: Font.DemiBold; font.family: root.font; renderType: Text.NativeRendering }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 22
                                height: 22
                                radius: 11
                                color: closeFoldMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                Text { anchors.centerIn: parent; text: "✕"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; renderType: Text.NativeRendering }
                                MouseArea {
                                    id: closeFoldMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeFolderInput()
                                }
                            }
                        }

                        // Text Input Field
                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 10
                            color: Qt.rgba(0, 0, 0, 0.45)
                            border.color: folderTextInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.14)
                            border.width: folderTextInput.activeFocus ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8

                                Text { text: "󰄲"; color: root.theme.textMuted; font.pixelSize: 12; font.family: root.font }

                                TextInput {
                                    id: folderTextInput
                                    Layout.fillWidth: true
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    selectByMouse: true
                                    selectionColor: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40)
                                    selectedTextColor: "#ffffff"
                                    clip: true

                                    Text {
                                        anchors.fill: parent
                                        text: "Enter folder path (e.g. ~/Pictures/Wallpapers)..."
                                        color: root.theme.textMuted
                                        font.pixelSize: 12
                                        font.family: root.font
                                        visible: !folderTextInput.text && !folderTextInput.activeFocus
                                    }

                                    Keys.onReturnPressed: root.applyFolderInput()
                                    Keys.onEscapePressed: root.closeFolderInput()
                                }

                                Rectangle {
                                    visible: folderTextInput.text.length > 0
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: clearFoldM.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                                    Text { anchors.centerIn: parent; text: "✕"; color: root.theme.textMuted; font.pixelSize: 9 }
                                    MouseArea {
                                        id: clearFoldM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { folderTextInput.text = ""; folderTextInput.forceActiveFocus(); }
                                    }
                                }
                            }
                        }

                        // Presets Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text { text: "Quick Presets:"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; renderType: Text.NativeRendering }

                            Repeater {
                                model: [
                                    { name: "Wallpapers", path: "/home/aran/Pictures/Wallpapers" },
                                    { name: "Pictures", path: "/home/aran/Pictures" },
                                    { name: "Screenshots", path: "/home/aran/Pictures/Screenshots" }
                                ]

                                Rectangle {
                                    height: 22
                                    radius: 11
                                    color: chipMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1
                                    Layout.preferredWidth: chipText.implicitWidth + 14

                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        color: root.theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: root.font
                                        renderType: Text.NativeRendering
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            folderTextInput.text = modelData.path;
                                            folderTextInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Actions Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                height: 30
                                radius: 8
                                color: cancelFoldM.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1
                                Layout.preferredWidth: 64

                                Text { anchors.centerIn: parent; text: "Cancel"; color: root.theme.textMuted; font.pixelSize: 11; font.family: root.font; renderType: Text.NativeRendering }
                                MouseArea {
                                    id: cancelFoldM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeFolderInput()
                                }
                            }

                            Rectangle {
                                height: 30
                                radius: 8
                                color: applyFoldM.pressed ? Qt.darker(root.theme.accent, 1.25) : (applyFoldM.containsMouse ? Qt.darker(root.theme.accent, 1.15) : root.theme.accent)
                                Layout.preferredWidth: applyFoldRow.implicitWidth + 18

                                RowLayout {
                                    id: applyFoldRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text { text: "󰄬"; color: "#090d16"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { text: "Apply Path"; color: "#090d16"; font.pixelSize: 11; font.weight: Font.DemiBold; font.family: root.font; renderType: Text.NativeRendering }
                                }

                                MouseArea {
                                    id: applyFoldM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.applyFolderInput()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
