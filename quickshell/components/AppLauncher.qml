import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
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
    property string calcResult: ""

    // ── IPC Handler for External Toggle ─────────────
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcherPanel.visible = !launcherPanel.visible;
            if (launcherPanel.visible) {
                searchInput.text = "";
                root.selectedIndex = 0;
                root.calcResult = "";
                searchInput.forceActiveFocus();
            }
        }
    }

    // ── Helpers ─────────────────────────────────────
    function evaluateMath(expr) {
        try {
            const clean = expr.trim().replace(/^=/, '').trim();
            if (!clean || !/^[0-9+\-*/().%^ eE]+$/.test(clean)) return "";
            const res = Function('"use strict"; return (' + clean + ')')();
            if (typeof res === "number" && !isNaN(res) && isFinite(res)) {
                return String(Math.round(res * 10000) / 10000);
            }
        } catch (e) {}
        return "";
    }

    function isUrl(text) {
        const t = text.trim();
        return /^https?:\/\/\S+/i.test(t) || /^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(\/\S*)?$/i.test(t);
    }

    function searchWeb(query) {
        const q = encodeURIComponent(query.trim());
        if (!q) return;
        Services.SystemService.runCmd("xdg-open 'https://www.google.com/search?q=" + q + "' || firefox 'https://www.google.com/search?q=" + q + "'");
        launcherPanel.visible = false;
    }

    function openUrl(url) {
        let target = url.trim();
        if (!target.startsWith("http://") && !target.startsWith("https://")) {
            target = "https://" + target;
        }
        Services.SystemService.runCmd("xdg-open '" + target + "' || firefox '" + target + "'");
        launcherPanel.visible = false;
    }

    function runTerminalCmd(cmd) {
        const clean = cmd.replace(/^>/, '').trim();
        if (!clean) return;
        Services.SystemService.runCmd("kitty --directory /home/aran -e " + clean + " || alacritty --working-directory /home/aran -e " + clean);
        launcherPanel.visible = false;
    }

    function launchApp(entry) {
        if (!entry) return;
        const name = (entry.name ?? "").toLowerCase();
        const id = (entry.id ?? "").toLowerCase();
        if (id.includes("screenlocker") || (name.includes("screen") && name.includes("lock"))) {
            launcherPanel.visible = false;
            Services.SystemService.lockScreen();
            return;
        }
        entry.execute();
        launcherPanel.visible = false;
    }

    // ── System Commands Matching ────────────────────
    function matchSystemCmd(q) {
        const query = q.trim().toLowerCase();
        if (!query) return null;
        if (query === "lock" || query === "lockscreen" || query === "lock screen") {
            return { name: "Lock Screen", desc: "Lock the current session", icon: "󰌾", action: () => Services.SystemService.lockScreen() };
        }
        if (query === "sleep" || query === "suspend") return { name: "Sleep / Suspend", desc: "Suspend system to RAM", icon: "󰤄", action: () => Services.SystemService.runCmd("systemctl suspend") };
        if (query === "logout" || query === "exit") return { name: "Log Out", desc: "Exit Hyprland session", icon: "󰍃", action: () => Services.SystemService.runCmd("hyprctl dispatch 'hl.dsp.exit()'") };
        if (query === "reboot" || query === "restart") return { name: "Restart Computer", desc: "Reboot the operating system", icon: "󰜉", action: () => Services.SystemService.runCmd("systemctl reboot") };
        if (query === "shutdown" || query === "poweroff") return { name: "Power Off", desc: "Shut down the computer", icon: "⏻", action: () => Services.SystemService.runCmd("systemctl poweroff") };
        return null;
    }

    // ── Filtered Applications Model ─────────────────
    ScriptModel {
        id: filteredApps
        objectProp: "id"
        values: {
            const all = [...DesktopEntries.applications.values];
            const q = searchInput.text.trim().toLowerCase();
            if (q === "" || q.startsWith(">")) return all.sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));

            return all.filter(d => {
                const name = (d.name ?? "").toLowerCase();
                const gen = (d.genericName ?? "").toLowerCase();
                const comment = (d.comment ?? "").toLowerCase();
                return name.includes(q) || gen.includes(q) || comment.includes(q);
            }).sort((a, b) => {
                const an = (a.name ?? "").toLowerCase();
                const bn = (b.name ?? "").toLowerCase();
                const aStarts = an.startsWith(q);
                const bStarts = bn.startsWith(q);
                if (aStarts && !bStarts) return -1;
                if (!aStarts && bStarts) return 1;
                return an.localeCompare(bn);
            });
        }
    }

    // ── Main Full-Screen Overlay Window ─────────────
    PanelWindow {
        id: launcherPanel
        visible: false
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "quickshell-spotlight"
        exclusionMode: ExclusionMode.Ignore

        BackgroundEffect.blurRegion: Region { item: spotlightBox }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Dark Blurred Backdrop (click to dismiss)
        Rectangle {
            anchors.fill: parent
            color: Services.Aesthetic.backdropColor

            MouseArea {
                anchors.fill: parent
                onClicked: launcherPanel.visible = false
            }
        }

        // ── Spotlight Floating Card ─────────────────
        Rectangle {
            id: spotlightBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.18

            width: 620
            height: {
                const q = searchInput.text.trim();
                const hasApps = filteredApps.values.length > 0;
                const hasSpecial = root.calcResult !== "" || q.startsWith(">") || root.matchSystemCmd(q) !== null || root.isUrl(q);

                if (q === "") return 440;
                if (!hasApps) return hasSpecial ? 200 : 180;
                return Math.min(520, Math.min(6, filteredApps.values.length) * 48 + (hasSpecial ? 180 : 130));
            }
            radius: Services.Aesthetic.cardRadius
            color: Services.Aesthetic.cardBg
            border.color: Services.Aesthetic.cardBorder
            border.width: Services.Aesthetic.borderWidth
            clip: true

            Behavior on height {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Stop click through
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ── Search Input Row ────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 12
                    color: root.theme.pillBg
                    border.color: searchInput.activeFocus ? root.theme.accent : root.theme.barBg
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            text: "󰍉"
                            color: root.theme.accent
                            font.pixelSize: 20
                            font.family: root.font
                            Layout.alignment: Qt.AlignVCenter
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            color: root.theme.textPrimary
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Medium
                            clip: true
                            focus: true

                            Text {
                                anchors.fill: parent
                                text: "Search apps, web, calculate, or > command..."
                                color: root.theme.textMuted
                                font: parent.font
                                visible: !parent.text && !parent.activeFocus
                                verticalAlignment: Text.AlignVCenter
                            }

                            onTextChanged: {
                                root.selectedIndex = 0;
                                root.calcResult = root.evaluateMath(text);
                            }

                            Keys.onEscapePressed: launcherPanel.visible = false

                            Keys.onPressed: (event) => {
                                const q = text.trim();
                                const sys = root.matchSystemCmd(q);
                                const isU = root.isUrl(q);

                                if (event.key === Qt.Key_Down) {
                                    event.accepted = true;
                                    root.selectedIndex = Math.min(root.selectedIndex + 1, filteredApps.values.length - 1);
                                    resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                } else if (event.key === Qt.Key_Up) {
                                    event.accepted = true;
                                    root.selectedIndex = Math.max(root.selectedIndex - 1, 0);
                                    resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;

                                    if (q.startsWith(">")) {
                                        root.runTerminalCmd(q);
                                    } else if (sys !== null) {
                                        launcherPanel.visible = false;
                                        sys.action();
                                    } else if (isU) {
                                        root.openUrl(q);
                                    } else if (root.calcResult !== "") {
                                        launcherPanel.visible = false;
                                    } else if (filteredApps.values.length > 0 && root.selectedIndex >= 0) {
                                        const entry = filteredApps.values[root.selectedIndex];
                                        if (entry) root.launchApp(entry);
                                    } else if (q !== "") {
                                        // No app found: perform web search
                                        root.searchWeb(q);
                                    }
                                } else if (event.key === Qt.Key_Tab) {
                                    event.accepted = true;
                                    root.selectedIndex = (root.selectedIndex + 1) % Math.max(1, filteredApps.values.length);
                                    resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                }
                            }
                        }

                        // Esc hint pill
                        Rectangle {
                            width: 38
                            height: 22
                            radius: 6
                            color: root.theme.barBg
                            Text {
                                anchors.centerIn: parent
                                text: "esc"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }
                    }
                }

                // ── Special Result Cards (Math / Terminal / System / URL) ──

                // 1. Math Evaluation Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 10
                    color: Qt.rgba(root.theme.accentGreen.r, root.theme.accentGreen.g, root.theme.accentGreen.b, 0.15)
                    border.color: root.theme.accentGreen
                    border.width: 1
                    visible: root.calcResult !== ""

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "󰃬"
                            color: root.theme.accentGreen
                            font.pixelSize: 20
                            font.family: root.font
                        }
                        Text {
                            text: "Calculation"
                            color: root.theme.textSecondary
                            font.pixelSize: 12
                            font.family: root.font
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "= " + root.calcResult
                            color: root.theme.accentGreen
                            font.pixelSize: 16
                            font.family: root.font
                            font.weight: Font.Bold
                        }
                    }
                }

                // 2. Terminal Run Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 10
                    color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.15)
                    border.color: root.theme.accent
                    border.width: 1
                    visible: searchInput.text.trim().startsWith(">")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "󰞷"
                            color: root.theme.accent
                            font.pixelSize: 20
                            font.family: root.font
                        }
                        Text {
                            text: "Run in terminal: " + searchInput.text.substring(1).trim()
                            color: root.theme.textPrimary
                            font.pixelSize: 12
                            font.family: root.font
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "↵ Enter"
                            color: root.theme.accent
                            font.pixelSize: 11
                            font.family: root.font
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runTerminalCmd(searchInput.text)
                    }
                }

                // 3. System Command Card (KRunner style)
                Rectangle {
                    id: sysCmdCard
                    property var sysCmd: root.matchSystemCmd(searchInput.text)
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 10
                    color: Qt.rgba(root.theme.accentOrange.r, root.theme.accentOrange.g, root.theme.accentOrange.b, 0.15)
                    border.color: root.theme.accentOrange
                    border.width: 1
                    visible: sysCmd !== null

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: sysCmdCard.sysCmd?.icon ?? "󰒓"
                            color: root.theme.accentOrange
                            font.pixelSize: 20
                            font.family: root.font
                        }
                        Column {
                            Layout.fillWidth: true
                            Text {
                                text: sysCmdCard.sysCmd?.name ?? ""
                                color: root.theme.textPrimary
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: sysCmdCard.sysCmd?.desc ?? ""
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                            }
                        }
                        Text {
                            text: "↵ Execute"
                            color: root.theme.accentOrange
                            font.pixelSize: 11
                            font.family: root.font
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            launcherPanel.visible = false;
                            sysCmdCard.sysCmd?.action();
                        }
                    }
                }

                // 4. URL Navigation Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 10
                    color: Qt.rgba(root.theme.accentMauve.r, root.theme.accentMauve.g, root.theme.accentMauve.b, 0.15)
                    border.color: root.theme.accentMauve
                    border.width: 1
                    visible: root.isUrl(searchInput.text)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "󰌷"
                            color: root.theme.accentMauve
                            font.pixelSize: 20
                            font.family: root.font
                        }
                        Column {
                            Layout.fillWidth: true
                            Text {
                                text: "Open URL: " + searchInput.text.trim()
                                color: root.theme.textPrimary
                                font.pixelSize: 12
                                font.family: root.font
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: 440
                            }
                            Text {
                                text: "Opens in default browser"
                                color: root.theme.textMuted
                                font.pixelSize: 10
                                font.family: root.font
                            }
                        }
                        Text {
                            text: "↵ Open"
                            color: root.theme.accentMauve
                            font.pixelSize: 11
                            font.family: root.font
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openUrl(searchInput.text)
                    }
                }

                // ── Web Search Suggestion Card ──────────────
                // Appears whenever no apps match, or query has no local app result
                Rectangle {
                    id: webSearchCard
                    readonly property bool shouldShow: searchInput.text.trim() !== "" &&
                                                       filteredApps.values.length === 0 &&
                                                       !searchInput.text.trim().startsWith(">") &&
                                                       root.matchSystemCmd(searchInput.text) === null &&
                                                       !root.isUrl(searchInput.text)

                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: 12
                    color: webSearchMouse.containsMouse ? root.theme.pillHover : root.theme.pillBg
                    border.color: root.theme.accent
                    border.width: 1
                    visible: shouldShow

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.2)
                            Text {
                                anchors.centerIn: parent
                                text: "󰖟"
                                color: root.theme.accent
                                font.pixelSize: 18
                                font.family: root.font
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            Text {
                                text: "Search Google for \"" + searchInput.text.trim() + "\""
                                color: root.theme.textPrimary
                                font.pixelSize: 13
                                font.family: root.font
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: 400
                            }
                            Text {
                                text: "No local apps found • Opens in your browser"
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }

                        Text {
                            text: "↵ Search"
                            color: root.theme.accent
                            font.pixelSize: 12
                            font.family: root.font
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: webSearchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.searchWeb(searchInput.text)
                    }
                }

                // ── Application Results List ────────────────
                ListView {
                    id: resultsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: filteredApps
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: root.selectedIndex
                    visible: filteredApps.values.length > 0 && !searchInput.text.trim().startsWith(">")

                    highlightMoveDuration: 120

                    highlight: Rectangle {
                        radius: 10
                        color: root.theme.pillHover
                        visible: root.selectedIndex >= 0

                        Rectangle {
                            width: 3
                            height: 20
                            radius: 1.5
                            color: root.theme.accent
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    delegate: Rectangle {
                        id: appDelegate
                        required property var modelData
                        required property int index

                        width: resultsList.width
                        height: 44
                        radius: 10
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            // App Icon
                            Item {
                                width: 28
                                height: 28
                                Layout.alignment: Qt.AlignVCenter

                                IconImage {
                                    anchors.fill: parent
                                    source: Quickshell.iconPath(appDelegate.modelData.icon ?? "", true)
                                    visible: (appDelegate.modelData.icon ?? "") !== ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰣆"
                                    color: root.theme.accent
                                    font.pixelSize: 18
                                    font.family: root.font
                                    visible: (appDelegate.modelData.icon ?? "") === ""
                                }
                            }

                            // Title & Description
                            Column {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    text: appDelegate.modelData.name ?? ""
                                    color: root.selectedIndex === appDelegate.index ? "#ffffff" : root.theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: root.font
                                    font.weight: root.selectedIndex === appDelegate.index ? Font.DemiBold : Font.Normal
                                }

                                Text {
                                    text: appDelegate.modelData.genericName || appDelegate.modelData.comment || "Application"
                                    color: root.theme.textMuted
                                    font.pixelSize: 10
                                    font.family: root.font
                                    elide: Text.ElideRight
                                    width: 380
                                }
                            }

                            // Launch action hint on active item
                            Text {
                                text: "↵"
                                color: root.theme.textMuted
                                font.pixelSize: 14
                                font.family: root.font
                                visible: root.selectedIndex === appDelegate.index
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = appDelegate.index
                            onClicked: root.launchApp(appDelegate.modelData)
                        }
                    }
                }
            }
        }
    }
}
