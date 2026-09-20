import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../bar" as Bar

Scope {
    id: root

    property Bar.Theme theme: Bar.Theme {}
    readonly property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    // ── Polkit Agent Backend ──────────────────────────
    PolkitAgent {
        id: polkitAgent
        // Default D-Bus path: /org/quickshell/Polkit
    }

    // Convenience aliases
    readonly property var flow: polkitAgent.flow
    readonly property bool authActive: polkitAgent.isActive
    readonly property string txtPrimary: root.theme.textPrimary
    readonly property string txtMuted: root.theme.textMuted

    // Test mode for UI verification
    property bool testMode: false
    property string testMessage: "Authentication is required to run the GParted Partition Editor as superuser"
    property string testPrompt: "Password:"

    // Password shake animation on failure
    property int shakeOffset: 0

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeOffset"; to: 12; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: -10; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 35; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: -5; duration: 35; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 30; easing.type: Easing.OutCubic }
    }

    readonly property bool flowFailed: root.flow ? root.flow.failed : false
    onFlowFailedChanged: {
        if (flowFailed) {
            shakeAnim.start();
        }
    }

    // ── IPC Interface for System & Testing ───────────
    IpcHandler {
        target: "polkit"

        function isRegistered(): bool {
            return polkitAgent.isRegistered;
        }

        function isActive(): bool {
            return polkitAgent.isActive || root.testMode;
        }

        function testOpen(): void {
            root.testMode = true;
        }

        function testClose(): void {
            root.testMode = false;
        }
    }

    // ── Full-Screen Overlay Window ────────────────────
    PanelWindow {
        id: polkitPanel
        visible: root.authActive || root.testMode
        focusable: true
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: polkitPanel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-polkit"
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        BackgroundEffect.blurRegion: Region { item: dialogCard }

        // ── Dimmed Backdrop ──────────────────────────
        Rectangle {
            anchors.fill: parent
            color: Services.Aesthetic.backdropColor

            MouseArea {
                anchors.fill: parent
                onClicked: cancelAuth()
            }
        }

        // ── Centered Authentication Card ─────────────
        Rectangle {
            id: dialogCard
            width: 420
            implicitHeight: cardContent.implicitHeight + 48
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.shakeOffset
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

            // Prevent backdrop clicks from closing inside the card
            MouseArea {
                anchors.fill: parent
                preventStealing: true
            }

            ColumnLayout {
                id: cardContent
                width: parent.width - 48
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 24
                spacing: 14

                // ── Header: Lock Icon + Title ────────
                RowLayout {
                    spacing: 14
                    Layout.fillWidth: true

                    // Shield icon with accent ring
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.12)
                        border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰌾"  // nf-md-lock
                            font.pixelSize: 22
                            font.family: root.font
                            color: root.theme.accent
                            renderType: Text.NativeRendering
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: "Authentication Required"
                            color: root.txtPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: root.font
                            renderType: Text.NativeRendering
                        }

                        Text {
                            text: root.flow ? root.flow.message : (root.testMode ? root.testMessage : "")
                            color: root.txtMuted
                            font.pixelSize: 11
                            font.family: root.font
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                            maximumLineCount: 3
                        }
                    }
                }

                // ── Divider ──────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // ── Error / Supplementary Message ────
                RowLayout {
                    visible: root.flow ? root.flow.failed : false
                    spacing: 6
                    Layout.fillWidth: true

                    Text {
                        text: "󰀦"  // nf-md-alert_circle
                        color: root.theme.accentRed
                        font.pixelSize: 13
                        font.family: root.font
                        renderType: Text.NativeRendering
                    }

                    Text {
                        text: {
                            if (!root.flow) return "";
                            if (root.flow.supplementaryMessage && root.flow.supplementaryIsError)
                                return root.flow.supplementaryMessage;
                            return "Authentication failed. Please try again.";
                        }
                        color: root.theme.accentRed
                        font.pixelSize: 11
                        font.family: root.font
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }

                // ── Password Input Field ─────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: passwordInput.activeFocus
                        ? root.theme.accent
                        : (root.flow && root.flow.failed ? root.theme.accentRed : Qt.rgba(1, 1, 1, 0.12))
                    border.width: 1.5

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: "󰯄"  // nf-md-form_textbox_password
                            color: passwordInput.activeFocus ? root.theme.accent : root.txtMuted
                            font.pixelSize: 15
                            font.family: root.font
                            renderType: Text.NativeRendering

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        TextInput {
                            id: passwordInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            color: root.txtPrimary
                            font.pixelSize: 13
                            font.family: root.font
                            echoMode: (root.flow && root.flow.responseVisible)
                                ? TextInput.Normal
                                : TextInput.Password
                            focus: true
                            clip: true

                            Text {
                                anchors.fill: parent
                                text: root.flow ? (root.flow.inputPrompt || "Password") : "Password"
                                color: root.txtMuted
                                font: parent.font
                                visible: !parent.text
                                verticalAlignment: Text.AlignVCenter
                                renderType: Text.NativeRendering
                            }

                            Keys.onReturnPressed: submitPassword()
                            Keys.onEnterPressed: submitPassword()
                            Keys.onEscapePressed: cancelAuth()
                        }
                    }
                }

                // ── Action Buttons ───────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Layout.topMargin: 2

                    // Cancel Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 8
                        color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.txtMuted
                            font.pixelSize: 12
                            font.family: root.font
                            font.weight: Font.Medium
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cancelAuth()
                        }
                    }

                    // Authenticate Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 8
                        color: authMouse.containsMouse
                            ? Qt.lighter(root.theme.accent, 1.15)
                            : root.theme.accent
                        border.color: Qt.lighter(root.theme.accent, 1.3)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "󰌆"  // nf-md-key
                                color: "#1e1e2e"
                                font.pixelSize: 13
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: "Authenticate"
                                color: "#1e1e2e"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: root.font
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: authMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: submitPassword()
                        }
                    }
                }

                // ── Footer Hint ──────────────────────
                Text {
                    text: "↵ Submit  ·  esc Cancel"
                    color: Qt.rgba(root.txtMuted.r, root.txtMuted.g, root.txtMuted.b, 0.5)
                    font.pixelSize: 9
                    font.family: root.font
                    Layout.alignment: Qt.AlignHCenter
                    renderType: Text.NativeRendering
                }
            }
        }

        // ── Auto-focus and clear password on show ────
        onVisibleChanged: {
            if (visible) {
                passwordInput.text = "";
                passwordInput.forceActiveFocus();
            }
        }
    }

    // ── Helper Functions ──────────────────────────────
    function cancelAuth() {
        if (root.testMode) {
            root.testMode = false;
            passwordInput.text = "";
            return;
        }
        if (root.flow) {
            root.flow.cancelAuthenticationRequest();
        }
        passwordInput.text = "";
    }

    function submitPassword() {
        if (root.testMode) {
            root.testMode = false;
            passwordInput.text = "";
            return;
        }
        if (root.flow && passwordInput.text.length > 0) {
            root.flow.submit(passwordInput.text);
            passwordInput.text = "";
        }
    }
}
