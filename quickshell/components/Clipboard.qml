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
    property bool isOpen: false

    Timer {
        id: clipCloseTimer
        interval: 180
        repeat: false
        onTriggered: {
            clipboardPanel.visible = false;
            Services.OverlayCoordinator.releaseExclusiveSurface("clipboard");
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            if (root.isOpen) {
                closePopup();
            } else {
                openPopup();
            }
        }

        function open(): void {
            openPopup();
        }

        function close(): void {
            closePopup();
        }

        function clear(): void {
            wipeHistory();
        }
    }

    Component.onCompleted: {
        Services.OverlayCoordinator.registerExclusiveSurface("clipboard",
            () => { openPopup(); },
            () => { closePopup(); }
        );
    }

    function openPopup() {
        clipCloseTimer.stop();
        Services.OverlayCoordinator.requestExclusiveSurface("clipboard");
        clipboardPanel.visible = true;
        root.isOpen = true;
        searchInput.text = "";
        root.selectedIndex = 0;
        root.statusMessage = "";
        fetchClipboard();
        Qt.callLater(() => {
            searchInput.forceActiveFocus();
        });
    }

    function closePopup() {
        if (!clipboardPanel.visible) return;
        root.isOpen = false;
        clipCloseTimer.restart();
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
        command: ["/home/aran/.config/quickshell/scripts/cliphist-fetch.sh"]
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
            const trimmed = preview.trim();

            let type = "text";
            let isImage = false;
            let isUrl = false;
            let isColor = false;
            let isCode = false;
            let thumbSource = "";
            let title = "";
            let subtitle = "";
            let dimensions = "";
            let fileSize = "";
            let format = "";

            // Check if item is a file URI or path
            let isLocalFile = false;
            let localPath = "";
            if (trimmed.startsWith("file://")) {
                try {
                    localPath = decodeURIComponent(trimmed.replace(/^file:\/\//, ""));
                    isLocalFile = true;
                } catch(e) {
                    localPath = trimmed.replace(/^file:\/\//, "");
                    isLocalFile = true;
                }
            } else if (trimmed.startsWith("/") && /\.(png|jpe?g|webp|gif|bmp|svg|pdf|zip|tar(?:\.gz)?|txt|mp4|mkv|mp3)$/i.test(trimmed)) {
                localPath = trimmed;
                isLocalFile = true;
            }

            // Check if item is binary image data or image file
            const isBinaryImage = /^\[\[\s*binary data/i.test(trimmed) || trimmed.includes("binary data") || trimmed.includes("PNG") || trimmed.includes("JFIF") || trimmed.includes("WEBP") || trimmed.includes("IHDR") || trimmed.charCodeAt(0) === 0x89;
            const isFileImage = isLocalFile && /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(localPath);

            if (isBinaryImage) {
                type = "image";
                isImage = true;
                thumbSource = "file:///tmp/quickshell_clip_thumbs/" + id + ".png";

                const dimMatch = trimmed.match(/(\d+)\s*x\s*(\d+)/i);
                if (dimMatch) dimensions = dimMatch[1] + " × " + dimMatch[2];

                const sizeMatch = trimmed.match(/(\d+(?:\.\d+)?\s*(?:KiB|MiB|GiB|B|KB|MB))/i);
                if (sizeMatch) fileSize = sizeMatch[1];

                const fmtMatch = trimmed.match(/\b(png|jpe?g|webp|gif|bmp|tiff|avif)\b/i);
                format = fmtMatch ? fmtMatch[1].toUpperCase() : "PNG";

                title = format + " Image" + (dimensions ? " (" + dimensions + ")" : "");
                subtitle = (fileSize ? fileSize + " • " : "") + format + " • Press ↵ to copy";
            } else if (isFileImage) {
                type = "image";
                isImage = true;
                thumbSource = "file://" + localPath;
                const fileName = localPath.split("/").pop() || "Image";
                title = fileName;
                subtitle = "Local Image • Press ↵ to copy PNG, ⇧↵ for path";
            } else if (isLocalFile) {
                type = "file";
                const fileName = localPath.split("/").pop() || "File";
                title = fileName;
                subtitle = "Local File • Press ↵ to copy file, ⇧↵ for path";
            } else if (/^https?:\/\/\S+/i.test(trimmed) || /^www\.\S+/i.test(trimmed)) {
                type = "url";
                isUrl = true;
                title = trimmed;
                subtitle = "Web Link • " + trimmed;
            } else if (/^#(?:[0-9a-fA-F]{3}){1,2}$|^rgba?\([0-9, ]+\)$/.test(trimmed)) {
                type = "color";
                isColor = true;
                title = trimmed;
                subtitle = "Color Hex • " + trimmed;
            } else if (trimmed.includes("\n") || trimmed.includes("function") || trimmed.includes("const ") || trimmed.includes("import ") || (trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("<") && trimmed.endsWith(">"))) {
                type = "code";
                isCode = true;
                const clean = trimmed.replace(/\r?\n|\r/g, " ").trim();
                title = clean.length > 90 ? (clean.substring(0, 90) + "…") : clean;
                const len = trimmed.length;
                const lineCount = trimmed.split("\n").length;
                subtitle = (lineCount > 1 ? (lineCount + " lines (" + len + " chars)") : (len + " characters")) + " • Code snippet";
            } else {
                const clean = trimmed.replace(/\r?\n|\r/g, " ").trim();
                title = clean.length > 90 ? (clean.substring(0, 90) + "…") : clean;
                const len = trimmed.length;
                const lineCount = trimmed.split("\n").length;
                subtitle = (lineCount > 1 ? (lineCount + " lines (" + len + " chars)") : (len + " characters")) + " • Plain text";
            }

            items.push({
                id: id,
                preview: preview,
                type: type,
                isImage: isImage,
                isLocalFile: isLocalFile,
                localPath: localPath,
                isUrl: isUrl,
                isColor: isColor,
                isCode: isCode,
                thumbSource: thumbSource,
                title: title,
                subtitle: subtitle,
                dimensions: dimensions,
                fileSize: fileSize,
                format: format
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
                return "image".includes(q) || "png".includes(q) || "screenshot".includes(q) || "photo".includes(q) || (item.title && item.title.toLowerCase().includes(q));
            }
            return item.preview.toLowerCase().includes(q);
        });
    }

    // ── Actions ─────────────────────────────────────
    function copyItem(item, mode) {
        if (!item) return;
        const m = mode || "auto";
        const cmd = "/home/aran/.config/quickshell/scripts/cliphist-copy.sh '" + item.id + "' " + m;
        runAction(cmd);
        closePopup();
    }

    function deleteItem(item) {
        if (!item) return;
        const cmd = "printf '%s\\t' " + item.id + " | cliphist delete; rm -f /tmp/quickshell_clip_thumbs/" + item.id + ".*";
        runAction(cmd);

        // Update local array immediately
        const newArr = root.clipboardItems.filter(i => i.id !== item.id);
        root.clipboardItems = newArr;
        if (root.selectedIndex >= root.filteredItems.length) {
            root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
        }
    }

    function wipeHistory() {
        runAction("cliphist wipe; rm -rf /tmp/quickshell_clip_thumbs/*");
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
            } else {
                Services.OverlayCoordinator.releaseExclusiveSurface("clipboard");
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
            opacity: root.isOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                onClicked: root.closePopup()
            }
        }

        // ── Floating Clipboard Card ─────────────────
        Rectangle {
            id: cardBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: root.isOpen ? (parent.height * 0.16) : (parent.height * 0.16 - 18)
            scale: root.isOpen ? 1.0 : 0.94
            opacity: root.isOpen ? 1.0 : 0.0

            width: 640
            height: Math.min(560, Math.max(220, root.filteredItems.length * 62 + 150))
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
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
                spacing: 10

                // ── Header: Search & Quick Actions ──────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Search Pill
                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: searchInput.activeFocus ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "󰍉"
                                color: searchInput.activeFocus ? root.theme.accent : root.theme.textMuted
                                font.pixelSize: 16
                                font.family: root.font
                                Layout.alignment: Qt.AlignVCenter
                                renderType: Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                color: root.theme.textPrimary
                                font.pixelSize: 13
                                font.family: root.font
                                font.weight: Font.Medium
                                clip: true
                                focus: true

                                Text {
                                    anchors.fill: parent
                                    text: "Search clipboard history..."
                                    color: root.theme.textMuted
                                    font: parent.font
                                    visible: !parent.text
                                    verticalAlignment: Text.AlignVCenter
                                    renderType: Text.NativeRendering
                                }

                                onTextChanged: {
                                    root.selectedIndex = 0;
                                }

                                Keys.onEscapePressed: root.closePopup()

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
                                            const item = root.filteredItems[root.selectedIndex];
                                            const mode = (event.modifiers & Qt.ShiftModifier) ? "text" : "auto";
                                            root.copyItem(item, mode);
                                        }
                                    } else if (event.key === Qt.Key_Delete || (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ShiftModifier))) {
                                        event.accepted = true;
                                        if (root.filteredItems.length > 0 && root.selectedIndex >= 0) {
                                            root.deleteItem(root.filteredItems[root.selectedIndex]);
                                        }
                                    }
                                }
                            }

                            // Clear search circular button
                            Rectangle {
                                visible: searchInput.text.length > 0
                                width: 20
                                height: 20
                                radius: 10
                                color: clearSearchMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.theme.textMuted
                                    font.pixelSize: 11
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: clearSearchMouse
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
                        height: 42
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
                            renderType: Text.NativeRendering
                        }
                    }

                    // Clear All Button
                    Rectangle {
                        id: clearBtn
                        height: 42
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
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "Clear"
                                color: clearArea.containsMouse ? "#ff453a" : root.theme.textMuted
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.family: root.font
                                renderType: Text.NativeRendering
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

                // ── Header Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
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
                            renderType: Text.NativeRendering
                        }

                        Text {
                            text: "Copy any text or image, and it will appear here automatically"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            opacity: 0.7
                            Layout.alignment: Qt.AlignHCenter
                            visible: !searchInput.text.trim()
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // ── Items List ──────────────────────────────
                ListView {
                    id: itemList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    visible: root.filteredItems.length > 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.filteredItems

                    delegate: Rectangle {
                        id: itemRow
                        width: itemList.width
                        height: itemData.isImage ? 56 : 44
                        radius: 8

                        readonly property bool isSelected: index === root.selectedIndex
                        readonly property var itemData: modelData

                        color: isSelected 
                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)
                            : (rowHover.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                        border.color: isSelected 
                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.40)
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
                                height: itemData.isImage ? 26 : 20
                                radius: 1.5
                                color: root.theme.accent
                                visible: itemRow.isSelected
                                Layout.alignment: Qt.AlignVCenter
                            }

                            // Quick Pick Index Badge (for top 9 items)
                            Rectangle {
                                width: 20
                                height: 20
                                radius: 5
                                color: itemRow.isSelected ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.3) : Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                visible: index < 9
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: String(index + 1)
                                    color: itemRow.isSelected ? "#ffffff" : root.theme.textMuted
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }
                            }

                            // Type Icon Badge or Image Thumbnail
                            Rectangle {
                                width: itemData.isImage ? 42 : 28
                                height: itemData.isImage ? 42 : 28
                                radius: 6
                                Layout.alignment: Qt.AlignVCenter
                                color: {
                                    if (itemData.isImage) return Qt.rgba(0, 0, 0, 0.35);
                                    if (itemData.isUrl) return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14);
                                    if (itemData.isColor) return Qt.rgba(root.theme.accentYellow.r, root.theme.accentYellow.g, root.theme.accentYellow.b, 0.14);
                                    if (itemData.isCode) return Qt.rgba(root.theme.accentMauve.r, root.theme.accentMauve.g, root.theme.accentMauve.b, 0.14);
                                    return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12);
                                }
                                border.color: itemData.isImage ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                                border.width: itemData.isImage ? 1 : 0
                                clip: true

                                // Thumbnail Image
                                Image {
                                    id: thumbImg
                                    anchors.fill: parent
                                    source: (itemData.isImage && itemData.thumbSource) ? itemData.thumbSource : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    cache: true
                                    visible: itemData.isImage && status === Image.Ready
                                }

                                // Fallback Icon / Type Icon
                                Text {
                                    anchors.centerIn: parent
                                    visible: !itemData.isImage || thumbImg.status !== Image.Ready
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
                                    font.pixelSize: itemData.isImage ? 16 : 14
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }
                            }

                            // Content Preview (Title & Subtitle)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: itemData.title || itemData.preview
                                    color: root.theme.textPrimary
                                    font.pixelSize: 12
                                    font.weight: itemRow.isSelected ? Font.DemiBold : Font.Normal
                                    font.family: root.font
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: itemData.subtitle || ""
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                }
                            }

                            // Delete Action Button
                            Rectangle {
                                width: 24
                                height: 24
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
                                    font.pixelSize: 12
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteItem(itemData)
                                }
                            }

                            // Secondary: Copy Path Button for local files
                            Rectangle {
                                height: 20
                                Layout.preferredWidth: copyPathText.implicitWidth + 12
                                radius: 5
                                color: copyPathArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                border.width: 1
                                visible: itemRow.isSelected && itemData.isLocalFile
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    id: copyPathText
                                    anchors.centerIn: parent
                                    text: "⇧↵ Path"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: copyPathArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyItem(itemData, "text")
                                }
                            }

                            // Return/Copy hint pill on selected row
                            Rectangle {
                                height: 20
                                Layout.preferredWidth: copyHintText.implicitWidth + 12
                                radius: 5
                                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)
                                border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
                                border.width: 1
                                visible: itemRow.isSelected
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                     id: copyHintText
                                     anchors.centerIn: parent
                                     text: itemData.isImage ? "↵ Copy PNG" : (itemData.isLocalFile ? "↵ Copy File" : "↵ Copy")
                                     color: root.theme.accent
                                     font.pixelSize: 10
                                     font.weight: Font.DemiBold
                                     font.family: root.font
                                     renderType: Text.NativeRendering
                                }

                                MouseArea {
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: Qt.PointingHandCursor
                                     onClicked: root.copyItem(itemData, "auto")
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

                // ── Footer Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Footer Bar ──────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.03)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10

                        RowLayout {
                            spacing: 10

                            Text {
                                text: "↑↓ Navigate"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                opacity: 0.5
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "↵ Copy"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                opacity: 0.5
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "Alt+1..9 Quick Pick"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                opacity: 0.5
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "Del Remove"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "•"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                opacity: 0.5
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "Esc Close"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.statusMessage ? root.statusMessage : "cliphist + wl-clipboard"
                            color: root.statusMessage ? root.theme.accent : root.theme.textMuted
                            font.pixelSize: 10
                            font.weight: root.statusMessage ? Font.Bold : Font.Normal
                            font.family: root.font
                            opacity: root.statusMessage ? 1.0 : 0.6
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }
}
