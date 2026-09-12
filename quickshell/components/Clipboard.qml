import Quickshell
import Quickshell.Io
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

    property var clipboardItems: []
    property int selectedIndex: 0
    property string statusMessage: ""

    // ── IPC Handler for External Toggle (Super + V) ─────────────
    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            clipboardPanel.visible = !clipboardPanel.visible;
            if (clipboardPanel.visible) {
                openPopup();
            }
        }

        function open(): void {
            clipboardPanel.visible = true;
            openPopup();
        }

        function close(): void {
            clipboardPanel.visible = false;
        }

        function clear(): void {
            wipeHistory();
        }
    }

    function openPopup() {
        Services.SystemService.closeAllPopups();
        searchInput.text = "";
        root.selectedIndex = 0;
        root.statusMessage = "";
        fetchClipboard();
        Qt.callLater(() => {
            searchInput.forceActiveFocus();
        });
    }

    // ── Command Runner ──────────────────────────────
    Process {
        id: actionProc
        command: ["sh", "-c", ""]
    }

    function runAction(cmd) {
        actionProc.running = false;
        actionProc.command = ["sh", "-c", cmd];
        actionProc.running = true;
    }

    // ── Fetch Clipboard via cliphist ────────────────
    Process {
        id: listProc
        command: ["cliphist", "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseCliphist(text);
            }
        }
    }

    function fetchClipboard() {
        listProc.running = false;
        listProc.running = true;
    }

    function parseCliphist(raw) {
        if (!raw) {
            root.clipboardItems = [];
            return;
        }

        const lines = raw.split("\n");
        const items = [];

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line || line.trim().length === 0) continue;

            const tabIdx = line.indexOf("\t");
            if (tabIdx === -1) continue;

            const id = line.substring(0, tabIdx).trim();
            const preview = line.substring(tabIdx + 1);

            let type = "text";
            let isImage = false;
            let isUrl = false;
            let isColor = false;
            let isCode = false;

            // Check if item is binary image data
            if (preview.includes("PNG") || preview.includes("JFIF") || preview.includes("WEBP") || preview.includes("IHDR") || preview.charCodeAt(0) === 0x89) {
                type = "image";
                isImage = true;
            } else {
                const trimmed = preview.trim();
                if (/^https?:\/\/\S+/i.test(trimmed) || /^www\.\S+/i.test(trimmed)) {
                    type = "url";
                    isUrl = true;
                } else if (/^#(?:[0-9a-fA-F]{3}){1,2}$|^rgba?\([0-9, ]+\)$/.test(trimmed)) {
                    type = "color";
                    isColor = true;
                } else if (trimmed.includes("\n") || trimmed.includes("function") || trimmed.includes("const ") || trimmed.includes("import ") || (trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("<") && trimmed.endsWith(">"))) {
                    type = "code";
                    isCode = true;
                }
            }

            items.push({
                id: id,
                preview: preview,
                type: type,
                isImage: isImage,
                isUrl: isUrl,
                isColor: isColor,
                isCode: isCode
            });
        }

        root.clipboardItems = items;
        if (root.selectedIndex >= items.length) {
            root.selectedIndex = Math.max(0, items.length - 1);
        }
    }

    // ── Filtered Items Model ────────────────────────
    readonly property var filteredItems: {
        const q = searchInput.text.trim().toLowerCase();
        if (!q) return clipboardItems;

        return clipboardItems.filter(item => {
            if (item.isImage) {
                return "image".includes(q) || "png".includes(q) || "screenshot".includes(q) || "photo".includes(q);
            }
            return item.preview.toLowerCase().includes(q);
        });
    }

    // ── Actions ─────────────────────────────────────
    function copyItem(item) {
        if (!item) return;
        const cmd = "printf '%s\\t' " + item.id + " | cliphist decode | wl-copy";
        runAction(cmd);
        clipboardPanel.visible = false;
    }

    function deleteItem(item) {
        if (!item) return;
        const cmd = "printf '%s\\t' " + item.id + " | cliphist delete";
        runAction(cmd);

        // Update local array immediately
        const newArr = root.clipboardItems.filter(i => i.id !== item.id);
        root.clipboardItems = newArr;
        if (root.selectedIndex >= root.filteredItems.length) {
            root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
        }
    }

    function wipeHistory() {
        runAction("cliphist wipe");
        root.clipboardItems = [];
        root.selectedIndex = 0;
        root.statusMessage = "Clipboard history cleared";
    }

    // ── Full-Screen Layer Overlay ───────────────────
    PanelWindow {
        id: clipboardPanel
        visible: false
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: clipboardPanel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-clipboard"
        exclusionMode: ExclusionMode.Ignore

        BackgroundEffect.blurRegion: Region { item: cardBox }

        onVisibleChanged: {
            if (visible) {
                openPopup();
            }
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Dimmed Backdrop (click to dismiss)
        Rectangle {
            anchors.fill: parent
            color: Services.Aesthetic.backdropColor

            MouseArea {
                anchors.fill: parent
                onClicked: clipboardPanel.visible = false
            }
        }

        // ── Floating Clipboard Card ─────────────────
        Rectangle {
            id: cardBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.16

            width: 640
            height: Math.min(560, Math.max(220, root.filteredItems.length * 62 + 150))
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

            Behavior on height {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Prevent clicks from dismissing when inside card
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── Header: Search & Quick Actions ──────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Search Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: searchInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: "󰍉"
                                color: searchInput.activeFocus ? root.theme.accent : root.theme.textMuted
                                font.pixelSize: 16
                                font.family: root.font
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                color: root.theme.textPrimary
                                font.pixelSize: 14
                                font.family: root.font
                                font.weight: Font.Medium
                                clip: true
                                focus: true

                                Text {
                                    anchors.fill: parent
                                    text: "Search clipboard history..."
                                    color: root.theme.textMuted
                                    font: parent.font
                                    visible: !parent.text && !parent.activeFocus
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onTextChanged: {
                                    root.selectedIndex = 0;
                                }

                                Keys.onEscapePressed: clipboardPanel.visible = false

                                Keys.onPressed: (event) => {
                                    // Alt + 1..9 instant copy
                                    if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                                        const idx = event.key - Qt.Key_1;
                                        if (idx >= 0 && idx < root.filteredItems.length) {
                                            event.accepted = true;
                                            root.copyItem(root.filteredItems[idx]);
                                            return;
                                        }
                                    }

                                    if (event.key === Qt.Key_Down) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.min(root.selectedIndex + 1, root.filteredItems.length - 1);
                                        itemList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Up) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0);
                                        itemList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        event.accepted = true;
                                        if (root.filteredItems.length > 0 && root.selectedIndex >= 0) {
                                            root.copyItem(root.filteredItems[root.selectedIndex]);
                                        }
                                    } else if (event.key === Qt.Key_Delete || (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ShiftModifier))) {
                                        event.accepted = true;
                                        if (root.filteredItems.length > 0 && root.selectedIndex >= 0) {
                                            root.deleteItem(root.filteredItems[root.selectedIndex]);
                                        }
                                    }
                                }
                            }

                            // Clear search button
                            Text {
                                text: "✕"
                                color: root.theme.textMuted
                                font.pixelSize: 12
                                font.family: root.font
                                visible: searchInput.text.length > 0
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchInput.text = "";
                                        searchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    // Count Badge
                    Rectangle {
                        height: 44
                        Layout.preferredWidth: countText.implicitWidth + 18
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: root.filteredItems.length + " items"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.family: root.font
                        }
                    }

                    // Clear All Button
                    Rectangle {
                        id: clearBtn
                        height: 44
                        Layout.preferredWidth: clearRow.implicitWidth + 20
                        radius: 12
                        color: clearArea.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                        border.color: clearArea.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.35) : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰆴"
                                color: clearArea.containsMouse ? "#ff453a" : root.theme.textMuted
                                font.pixelSize: 13
                                font.family: root.font
                            }

                            Text {
                                text: "Clear"
                                color: clearArea.containsMouse ? "#ff453a" : root.theme.textMuted
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.family: root.font
                            }
                        }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.wipeHistory()
                        }
                    }
                }

                // ── Empty State ─────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.filteredItems.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: searchInput.text.trim() ? "󰍉" : "󰅍"
                            color: root.theme.textMuted
                            font.pixelSize: 40
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                            opacity: 0.5
                        }

                        Text {
                            text: searchInput.text.trim() ? ("No clips matching \"" + searchInput.text.trim() + "\"") : "Clipboard history is empty"
                            color: root.theme.textMuted
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            font.family: root.font
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Copy any text or image, and it will appear here automatically"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            opacity: 0.7
                            Layout.alignment: Qt.AlignHCenter
                            visible: !searchInput.text.trim()
                        }
                    }
                }

                // ── Items List ──────────────────────────────
                ListView {
                    id: itemList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    visible: root.filteredItems.length > 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.filteredItems

                    delegate: Rectangle {
                        id: itemRow
                        width: itemList.width
                        height: 52
                        radius: 10

                        readonly property bool isSelected: index === root.selectedIndex
                        readonly property var itemData: modelData

                        color: isSelected 
                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.16)
                            : (rowHover.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                        border.color: isSelected 
                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                            : "transparent"
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 10

                            // Left Accent Indicator Pill
                            Rectangle {
                                width: 3
                                height: 22
                                radius: 1.5
                                color: root.theme.accent
                                visible: itemRow.isSelected
                                Layout.alignment: Qt.AlignVCenter
                            }

                            // Quick Pick Index Badge (for top 9 items)
                            Rectangle {
                                width: 20
                                height: 20
                                radius: 6
                                color: itemRow.isSelected ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3) : Qt.rgba(1, 1, 1, 0.05)
                                visible: index < 9
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: String(index + 1)
                                    color: itemRow.isSelected ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: root.font
                                }
                            }

                            // Type Icon Badge
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 8
                                Layout.alignment: Qt.AlignVCenter
                                color: {
                                    if (itemData.isImage) return Qt.rgba(root.theme.accentPink.r, root.theme.accentPink.g, root.theme.accentPink.b, 0.14);
                                    if (itemData.isUrl) return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14);
                                    if (itemData.isColor) return Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.14);
                                    if (itemData.isCode) return Qt.rgba(root.theme.accentMauve.r, root.theme.accentMauve.g, root.theme.accentMauve.b, 0.14);
                                    return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12);
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        if (itemData.isImage) return "󰋩";
                                        if (itemData.isUrl) return "󰌹";
                                        if (itemData.isColor) return "󰏘";
                                        if (itemData.isCode) return "󰘐";
                                        return "󰅍";
                                    }
                                    color: {
                                        if (itemData.isImage) return root.theme.accentPink;
                                        if (itemData.isUrl) return root.theme.accent;
                                        if (itemData.isColor) return root.theme.accentYellow;
                                        if (itemData.isCode) return root.theme.accentMauve;
                                        return root.theme.accent;
                                    }
                                    font.pixelSize: 15
                                    font.family: root.font
                                }
                            }

                            // Content Preview (Title & Subtitle)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (itemData.isImage) {
                                            return "Image Clip (" + (itemData.preview.includes("PNG") ? "PNG" : "Image") + ")";
                                        }
                                        const clean = itemData.preview.replace(/\r?\n|\r/g, " ").trim();
                                        return clean.length > 90 ? (clean.substring(0, 90) + "…") : clean;
                                    }
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.weight: itemRow.isSelected ? Font.DemiBold : Font.Normal
                                    font.family: root.font
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (itemData.isImage) return "Image snippet • Press ↵ to copy";
                                        if (itemData.isUrl) return "Web Link • " + itemData.preview.trim();
                                        if (itemData.isColor) return "Color Hex • " + itemData.preview.trim();
                                        const len = itemData.preview.length;
                                        const lines = itemData.preview.split("\n").length;
                                        if (lines > 1) {
                                            return lines + " lines (" + len + " chars) • Multi-line text";
                                        }
                                        return len + " characters • Plain text";
                                    }
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    elide: Text.ElideRight
                                }
                            }

                            // Delete Action Button
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: delArea.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.18) : "transparent"
                                border.color: delArea.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.4) : "transparent"
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter
                                visible: itemRow.isSelected || rowHover.containsMouse
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: delArea.containsMouse ? "#ff5c50" : root.theme.textMuted
                                    font.pixelSize: 13
                                    font.family: root.font
                                }

                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteItem(itemData)
                                }
                            }

                            // Return/Copy hint pill on selected row
                            Rectangle {
                                height: 22
                                Layout.preferredWidth: copyHintText.implicitWidth + 12
                                radius: 6
                                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.20)
                                visible: itemRow.isSelected
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                     id: copyHintText
                                     anchors.centerIn: parent
                                     text: "↵ Copy"
                                     color: root.theme.accent
                                     font.pixelSize: 10
                                     font.weight: Font.DemiBold
                                     font.family: root.font
                                }
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onEntered: root.selectedIndex = index
                            onClicked: root.copyItem(itemData)
                        }
                    }
                }

                // ── Footer Bar ──────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.03)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        RowLayout {
                            spacing: 12

                            Text {
                                text: "↑↓ Navigate"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                opacity: 0.5
                            }

                            Text {
                                text: "↵ Copy"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                opacity: 0.5
                            }

                            Text {
                                text: "Alt+1..9 Quick Pick"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                opacity: 0.5
                            }

                            Text {
                                text: "Del Remove"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                opacity: 0.5
                            }

                            Text {
                                text: "Esc Close"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.statusMessage ? root.statusMessage : "cliphist + wl-clipboard"
                            color: root.statusMessage ? root.theme.accent : root.theme.textMuted
                            font.pixelSize: 11
                            font.weight: root.statusMessage ? Font.Bold : Font.Normal
                            font.family: root.font
                            opacity: root.statusMessage ? 1.0 : 0.6
                        }
                    }
                }
            }
        }
    }
}
