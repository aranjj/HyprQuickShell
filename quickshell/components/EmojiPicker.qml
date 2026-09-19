import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../bar" as Bar
import "../services" as Services
import "EmojiSearch.js" as EmojiSearch

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    property bool cursorActive: false
    property var emojis: []
    property var filteredEmojis: []
    property string activeCategory: "All"
    property var recentEmojis: []

    // ── Dimensions & Layout ──────────────────────────
    readonly property int cardWidth: 440
    readonly property int cardHeight: 520
    readonly property int cellWidth: 44
    readonly property int cellHeight: 44
    readonly property int columns: 9

    // ── Categories List ──────────────────────────────
    readonly property var categoryList: [
        { id: "All", name: "All", icon: "󰍉" },
        { id: "Recent", name: "Recent", icon: "󰄉" },
        { id: "Smileys & Emotion", name: "Smileys", icon: "😀" },
        { id: "People & Body", name: "People", icon: "👋" },
        { id: "Animals & Nature", name: "Animals", icon: "🐱" },
        { id: "Food & Drink", name: "Food", icon: "🍔" },
        { id: "Travel & Places", name: "Travel", icon: "🚀" },
        { id: "Activities", name: "Activity", icon: "⚽" },
        { id: "Objects", name: "Objects", icon: "💡" },
        { id: "Symbols", name: "Symbols", icon: "❤️" },
        { id: "Flags", name: "Flags", icon: "🏁" }
    ]

    // ── IPC Handler for External Toggle (Super + Ctrl + E or Super + .) ──
    IpcHandler {
        target: "emojis"

        function toggle(): void {
            if (emojiPanel.visible) {
                root.dismiss();
            } else {
                root.open();
            }
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.dismiss();
        }

        function query(text: string): void {
            root.open();
            root.setFilter(text);
        }
    }

    // ── Load Emoji Database ──────────────────────────
    FileView {
        id: emojiDataFile
        path: "/home/aran/.config/quickshell/data/emojis.json"
        preload: true
        blockLoading: true
        onLoaded: {
            root.loadEmojis(text());
        }
    }

    // ── Load Recents File ────────────────────────────
    FileView {
        id: recentsDataFile
        path: "/home/aran/.config/quickshell/data/recent_emojis.json"
        preload: true
        blockLoading: true
        onLoaded: {
            try {
                var parsed = JSON.parse(text().trim());
                if (Array.isArray(parsed)) {
                    root.recentEmojis = parsed;
                }
            } catch (e) {
                root.recentEmojis = [];
            }
        }
    }

    Component.onCompleted: {
        try {
            var raw = emojiDataFile.text();
            if (raw && raw.length > 0) {
                root.loadEmojis(raw);
            }
        } catch (e) {}

        try {
            var rec = recentsDataFile.text();
            if (rec && rec.length > 0) {
                var p = JSON.parse(rec.trim());
                if (Array.isArray(p)) root.recentEmojis = p;
            }
        } catch (e) {}
    }

    // ── Process to Copy & Insert Emoji and Save Recents ───────
    Process {
        id: actionProc
        command: ["/home/aran/.config/quickshell/scripts/emoji-insert.sh", ""]
    }

    function applySelected(emoji) {
        if (!emoji) return;

        // Copy to Wayland clipboard and auto-paste into active typing surface
        actionProc.running = false;
        actionProc.command = ["/home/aran/.config/quickshell/scripts/emoji-insert.sh", emoji];
        actionProc.running = true;

        // Record to recents
        saveRecent(emoji);

        root.dismiss();
    }

    Process {
        id: saveRecentsProc
        command: ["sh", "-c", ""]
    }

    function saveRecent(emoji) {
        if (!emoji) return;
        var list = root.recentEmojis.filter(function(e) { return e !== emoji; });
        list.unshift(emoji);
        if (list.length > 36) list = list.slice(0, 36);
        root.recentEmojis = list;

        var jsonStr = JSON.stringify(list);
        saveRecentsProc.running = false;
        saveRecentsProc.command = ["sh", "-c", "printf '%s' \"$1\" > /home/aran/.config/quickshell/data/recent_emojis.json", "_", jsonStr];
        saveRecentsProc.running = true;
    }

    property real openTime: 0

    // ── State Management & Interaction ───────────────
    function open() {
        Services.SystemService.closeAllPopups();
        root.openTime = Date.now();
        root.opened = true;
        emojiPanel.visible = true;
        if (searchInput.text !== "") {
            searchInput.text = "";
        }
        root.filterText = "";
        root.selectedIndex = 0;
        root.cursorActive = true;
        root.rebuildDisplay();
        Qt.callLater(function() {
            searchInput.forceActiveFocus();
        });
    }

    function close() {
        root.dismiss();
    }

    function dismiss() {
        root.opened = false;
        emojiPanel.visible = false;
    }

    function toggle() {
        if (emojiPanel.visible) root.dismiss();
        else root.open();
    }

    function loadEmojis(raw) {
        root.emojis = EmojiSearch.parseEmojis(raw);
        if (root.opened) root.rebuildDisplay();
    }

    function rebuildDisplay() {
        var baseList = root.emojis;

        if (root.activeCategory === "Recent") {
            var recents = [];
            for (var r = 0; r < root.recentEmojis.length; r++) {
                var found = root.emojis.find(function(item) { return item.e === root.recentEmojis[r]; });
                if (found) {
                    recents.push(found);
                } else {
                    recents.push({ e: root.recentEmojis[r], n: "recent emoji", g: "Recent", s: "" });
                }
            }
            baseList = recents;
        } else if (root.activeCategory !== "All") {
            baseList = root.emojis.filter(function(item) { return item.g === root.activeCategory; });
        }

        var out = EmojiSearch.filterEmojis(baseList, root.filterText, 1000);
        root.filteredEmojis = out;

        var batch = [];
        for (var j = 0; j < out.length; j++) {
            batch.push({
                emoji: out[j].e,
                name: out[j].n || "",
                group: out[j].g || "",
                itemIndex: j
            });
        }

        displayModel.clear();
        displayModel.append(batch);

        if (displayModel.count === 0) selectedIndex = 0;
        else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0) selectedIndex = 0;
        cursorActive = displayModel.count > 0;

        Qt.callLater(function() {
            if (displayModel.count > 0) {
                resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
            }
        });
    }

    function select(delta) {
        if (displayModel.count === 0) return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
        } else {
            selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
        }
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function selectRow(delta) {
        if (displayModel.count === 0) return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
            resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
            return;
        }
        var newIndex = selectedIndex + delta * columns;
        if (newIndex < 0) newIndex = 0;
        if (newIndex >= displayModel.count) newIndex = displayModel.count - 1;
        selectedIndex = newIndex;
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function selectPage(delta) {
        if (displayModel.count === 0) return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
            resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
            return;
        }
        var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight));
        var newIndex = selectedIndex + delta * columns * visibleRows;
        if (newIndex < 0) newIndex = 0;
        if (newIndex >= displayModel.count) newIndex = displayModel.count - 1;
        selectedIndex = newIndex;
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function setFilter(nextFilter) {
        root.filterText = nextFilter;
        if (searchInput.text !== nextFilter) {
            searchInput.text = nextFilter;
        }
        root.selectedIndex = 0;
        root.cursorActive = true;
        root.rebuildDisplay();
    }

    function cycleCategory(direction) {
        var list = root.categoryList;
        var idx = 0;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === root.activeCategory) {
                idx = i;
                break;
            }
        }
        var nextIdx = (idx + direction + list.length) % list.length;
        root.activeCategory = list[nextIdx].id;
        root.selectedIndex = 0;
        root.rebuildDisplay();
    }

    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count) return;
        var row = displayModel.get(index);
        root.applySelected(row.emoji);
    }

    // Active Item Details
    readonly property var currentItem: (displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count) ? displayModel.get(selectedIndex) : null
    readonly property string currentEmojiChar: currentItem ? currentItem.emoji : ""
    readonly property string currentEmojiName: currentItem ? currentItem.name : ""
    readonly property string currentEmojiGroup: currentItem ? currentItem.group : ""

    ListModel { id: displayModel }

    // ── Full-Screen Layer Overlay ───────────────────
    PanelWindow {
        id: emojiPanel
        visible: false
        focusable: true
        color: "transparent"

        WlrLayershell.namespace: "quickshell-emojis"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: emojiPanel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        BackgroundEffect.blurRegion: Region { item: cardBox }

        // Dimmed Backdrop (click to dismiss)
        Rectangle {
            anchors.fill: parent
            color: Services.Aesthetic.backdropColor

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (Date.now() - root.openTime < 250) return;
                    root.dismiss();
                }
            }
        }

        // ── Floating Emoji Card ─────────────────────
        Rectangle {
            id: cardBox
            anchors.centerIn: parent
            width: root.cardWidth
            height: root.cardHeight
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

            // Stop click bubbling
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ── Search Pill ──────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 42
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: searchInput.activeFocus ? root.theme.accent : (root.filterText ? root.theme.accent : Qt.rgba(1, 1, 1, 0.08))
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            Behavior on color { ColorAnimation { duration: 150 } }
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
                                text: "Search emojis (e.g. fire, smile, rocket)..."
                                color: root.theme.textMuted
                                font: parent.font
                                visible: !parent.text
                                verticalAlignment: Text.AlignVCenter
                                renderType: Text.NativeRendering
                            }

                            onTextChanged: {
                                if (root.filterText !== text) {
                                    root.filterText = text;
                                    root.selectedIndex = 0;
                                    root.cursorActive = true;
                                    root.rebuildDisplay();
                                }
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    if (text.length > 0) {
                                        text = "";
                                    } else {
                                        root.dismiss();
                                    }
                                } else if (event.key === Qt.Key_Left) {
                                    event.accepted = true;
                                    root.select(-1);
                                } else if (event.key === Qt.Key_Right) {
                                    event.accepted = true;
                                    root.select(1);
                                } else if (event.key === Qt.Key_Up) {
                                    event.accepted = true;
                                    root.selectRow(-1);
                                } else if (event.key === Qt.Key_Down) {
                                    event.accepted = true;
                                    root.selectRow(1);
                                } else if (event.key === Qt.Key_PageUp) {
                                    event.accepted = true;
                                    root.selectPage(-1);
                                } else if (event.key === Qt.Key_PageDown) {
                                    event.accepted = true;
                                    root.selectPage(1);
                                } else if (event.key === Qt.Key_Tab) {
                                    event.accepted = true;
                                    root.cycleCategory(1);
                                } else if (event.key === Qt.Key_Backtab) {
                                    event.accepted = true;
                                    root.cycleCategory(-1);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;
                                    if (Date.now() - root.openTime < 300) return;
                                    if (displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
                                        root.activateIndex(root.selectedIndex);
                                    }
                                }
                            }
                        }

                        // Clear Button
                        Rectangle {
                            visible: root.filterText.length > 0
                            width: 20
                            height: 20
                            radius: 10
                            color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
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
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setFilter("")
                            }
                        }
                    }
                }

                // ── Search Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Category Selector Bar ────────────
                Flickable {
                    Layout.fillWidth: true
                    height: 28
                    contentWidth: categoryRow.width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: categoryRow
                        spacing: 6

                        Repeater {
                            model: root.categoryList

                            Rectangle {
                                id: catPill
                                width: catText.implicitWidth + 18
                                height: 26
                                radius: 13
                                color: {
                                    if (root.activeCategory === modelData.id) {
                                        return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18);
                                    }
                                    if (catMouse.containsMouse) {
                                        return Qt.rgba(1, 1, 1, 0.08);
                                    }
                                    return "transparent";
                                }
                                border.color: {
                                    if (root.activeCategory === modelData.id) {
                                        return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45);
                                    }
                                    if (catMouse.containsMouse) {
                                        return Qt.rgba(1, 1, 1, 0.12);
                                    }
                                    return Qt.rgba(1, 1, 1, 0.05);
                                }
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                Row {
                                    id: catText
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: modelData.icon
                                        font.pixelSize: 11
                                        font.family: root.font
                                        verticalAlignment: Text.AlignVCenter
                                        renderType: Text.NativeRendering
                                    }

                                    Text {
                                        text: modelData.name
                                        color: root.activeCategory === modelData.id ? root.theme.accent : (catMouse.containsMouse ? root.theme.textPrimary : root.theme.textMuted)
                                        font.pixelSize: 11
                                        font.family: root.font
                                        font.weight: root.activeCategory === modelData.id ? Font.DemiBold : Font.Normal
                                        verticalAlignment: Text.AlignVCenter
                                        renderType: Text.NativeRendering
                                    }
                                }

                                MouseArea {
                                    id: catMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeCategory = modelData.id;
                                        root.selectedIndex = 0;
                                        root.rebuildDisplay();
                                        searchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Category Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Emoji Grid View ──────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    GridView {
                        id: resultGrid
                        anchors.fill: parent
                        model: displayModel
                        cellWidth: root.cellWidth
                        cellHeight: root.cellHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property int itemIndex
                            required property string emoji
                            required property string name
                            required property string group

                            readonly property bool isSelected: root.cursorActive && itemIndex === root.selectedIndex

                            width: root.cellWidth
                            height: root.cellHeight
                            radius: 8
                            color: {
                                if (isSelected) {
                                    return Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.22);
                                }
                                if (cellMouse.containsMouse) {
                                    return Qt.rgba(1, 1, 1, 0.08);
                                }
                                return "transparent";
                            }
                            border.color: isSelected ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.45) : "transparent"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 80 } }
                            Behavior on border.color { ColorAnimation { duration: 80 } }

                            Text {
                                text: parent.emoji
                                font.pixelSize: 22
                                font.family: root.font
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: {
                                    if (containsMouse) {
                                        root.cursorActive = true;
                                        root.selectedIndex = itemIndex;
                                    }
                                }
                                onClicked: {
                                    if (Date.now() - root.openTime < 250) return;
                                    root.cursorActive = true;
                                    root.selectedIndex = itemIndex;
                                    root.activateIndex(itemIndex);
                                }
                            }
                        }
                    }

                    // Empty State
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: displayModel.count === 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰅖"
                            color: root.theme.textMuted
                            font.pixelSize: 32
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No emojis found"
                            color: root.theme.textPrimary
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.filterText ? ("No matches for \"" + root.filterText + "\"") : "No recent emojis yet"
                            color: root.theme.textMuted
                            font.pixelSize: 12
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // ── Footer Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Bottom Preview & Helper Bar ──────
                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.03)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        // Preview emoji
                        Text {
                            visible: root.currentEmojiChar.length > 0
                            text: root.currentEmojiChar
                            font.pixelSize: 18
                            font.family: root.font
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Name and group
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: {
                                if (root.currentEmojiName.length > 0) {
                                    var cap = root.currentEmojiName.charAt(0).toUpperCase() + root.currentEmojiName.slice(1);
                                    return cap + (root.currentEmojiGroup ? (" • " + root.currentEmojiGroup) : "");
                                }
                                return "Select an emoji to copy";
                            }
                            color: root.theme.textSecondary
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.family: root.font
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }

                        // Shortcut hint
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            Rectangle {
                                height: 20
                                width: enterHintText.implicitWidth + 10
                                radius: 5
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1

                                Text {
                                    id: enterHintText
                                    anchors.centerIn: parent
                                    text: "↵ Copy"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }
                            }

                            Rectangle {
                                height: 20
                                width: escHintText.implicitWidth + 10
                                radius: 5
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1

                                Text {
                                    id: escHintText
                                    anchors.centerIn: parent
                                    text: "Esc"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    renderType: Text.NativeRendering
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
