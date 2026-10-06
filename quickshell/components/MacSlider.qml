import QtQuick
import QtQuick.Layouts
import "../services" as Services

Item {
    id: root

    // ── Public API ──
    property real value: 0.0
    property real from: 0.0
    property real to: 100.0
    property real stepSize: 1.0

    // "large" (28px row, 5px track) | "medium" (24px row, 4px track) | "thin" (18px row, 4px track)
    property string size: "large"

    // Icons
    property string leftIcon: icon
    property string icon: ""
    property string rightIcon: ""

    property bool muted: false
    property bool enabled: true
    property bool accentFill: false
    property color accentColor: Services.ThemeService.accent

    property bool iconClickable: false
    property bool leftIconClickable: iconClickable
    property bool rightIconClickable: false

    property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    signal iconClicked()
    signal leftIconClicked()
    signal rightIconClicked()
    signal moved(real value)
    signal committed(real value)
    signal wheeled(real value)

    // ── Internal State ──
    property bool isDragging: false
    property real dragValue: value
    property bool hasPendingMoved: false

    readonly property real displayValue: isDragging ? dragValue : value

    readonly property real norm: {
        const span = to - from;
        if (span <= 0) return 0.0;
        const v = isDragging ? dragValue : value;
        return Math.max(0.0, Math.min(1.0, (v - from) / span));
    }

    // Follow external changes with 100ms OutCubic animation; disable during drag for 0 lag
    property real visualNorm: norm
    Behavior on visualNorm {
        enabled: !root.isDragging && !trackMouseArea.pressed
        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }

    implicitWidth: 200
    implicitHeight: {
        if (size === "medium") return 24;
        if (size === "thin") return 18;
        return 28; // "large"
    }

    opacity: enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: 150 } }

    activeFocusOnTab: enabled

    // Sizing tokens by variant
    readonly property real trackHeight: size === "large" ? 5 : 4
    readonly property real handleWidth: {
        if (size === "medium") return 26;
        if (size === "thin") return 18;
        return 32; // "large"
    }
    readonly property real handleHeight: {
        if (size === "medium") return 16;
        if (size === "thin") return 12;
        return 20; // "large"
    }
    readonly property real handleRadius: handleHeight / 2

    // Icon definitions
    readonly property bool hasLeftIcon: (size !== "thin") && (leftIcon !== "")
    readonly property bool hasRightIcon: (size === "large") && (rightIcon !== "")

    readonly property real leftIconWidth: hasLeftIcon ? 18 : 0
    readonly property real rightIconWidth: hasRightIcon ? 20 : 0
    readonly property real iconGap: 10

    // Handle center and fill bounds
    readonly property real trackAvail: Math.max(0, track.width - handleWidth)
    readonly property real handleCenterX: (handleWidth / 2) + visualNorm * trackAvail
    readonly property bool handleActive: (trackMouseArea.containsMouse || isDragging) && enabled

    // Helpers
    function valueFromX(mouseX) {
        const span = to - from;
        if (track.width <= 0 || span <= 0) return from;
        const ratio = Math.max(0.0, Math.min(1.0, mouseX / track.width));
        let v = from + ratio * span;
        if (stepSize > 0) {
            v = Math.round((v - from) / stepSize) * stepSize + from;
        }
        return Math.max(from, Math.min(to, v));
    }

    function applyDrag(mouseX) {
        dragValue = valueFromX(mouseX);
        if (size !== "thin") {
            if (!throttleTimer.running) {
                moved(dragValue);
                throttleTimer.start();
            } else {
                hasPendingMoved = true;
            }
        }
    }

    Timer {
        id: throttleTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.isDragging && root.hasPendingMoved && root.size !== "thin") {
                root.hasPendingMoved = false;
                root.moved(root.dragValue);
                throttleTimer.start();
            }
        }
    }

    // ── Keyboard Navigation ──
    Keys.onPressed: (event) => {
        if (!root.enabled) return;
        const span = to - from;
        const step2 = stepSize > 0 ? Math.max(stepSize, span * 0.02) : span * 0.02;
        const step10 = stepSize > 0 ? Math.max(stepSize, span * 0.10) : span * 0.10;

        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            event.accepted = true;
            const newVal = Math.max(from, Math.min(to, value - step2));
            committed(newVal);
            wheeled(newVal);
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            event.accepted = true;
            const newVal = Math.max(from, Math.min(to, value + step2));
            committed(newVal);
            wheeled(newVal);
        } else if (event.key === Qt.Key_PageDown) {
            event.accepted = true;
            const newVal = Math.max(from, Math.min(to, value - step10));
            committed(newVal);
            wheeled(newVal);
        } else if (event.key === Qt.Key_PageUp) {
            event.accepted = true;
            const newVal = Math.max(from, Math.min(to, value + step10));
            committed(newVal);
            wheeled(newVal);
        } else if (event.key === Qt.Key_Home) {
            event.accepted = true;
            committed(from);
            wheeled(from);
        } else if (event.key === Qt.Key_End) {
            event.accepted = true;
            committed(to);
            wheeled(to);
        }
    }

    // ═══════════════════════════════════════════
    // LEFT ICON (Small icon at left end)
    // ═══════════════════════════════════════════
    Item {
        id: leftIconBox
        visible: root.hasLeftIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.leftIconWidth
        height: parent.height

        Text {
            anchors.centerIn: parent
            text: root.leftIcon
            color: root.muted ? Services.ThemeService.textMuted : Services.ThemeService.textSecondary
            font.pixelSize: 12
            font.family: root.font
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        MouseArea {
            id: leftIconMouse
            anchors.fill: parent
            enabled: root.enabled && root.leftIconClickable
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                root.leftIconClicked();
                root.iconClicked();
            }
        }
    }

    // ═══════════════════════════════════════════
    // RIGHT ICON (Larger icon at right end)
    // ═══════════════════════════════════════════
    Item {
        id: rightIconBox
        visible: root.hasRightIcon
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.rightIconWidth
        height: parent.height

        Text {
            anchors.centerIn: parent
            text: root.rightIcon
            color: Services.ThemeService.textSecondary
            font.pixelSize: 16
            font.family: root.font
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        MouseArea {
            id: rightIconMouse
            anchors.fill: parent
            enabled: root.enabled && root.rightIconClickable
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.rightIconClicked()
        }
    }

    // ═══════════════════════════════════════════
    // SLIDER TRACK & FILL
    // ═══════════════════════════════════════════
    Item {
        id: track
        anchors.left: root.hasLeftIcon ? leftIconBox.right : parent.left
        anchors.leftMargin: root.hasLeftIcon ? root.iconGap : 0
        anchors.right: root.hasRightIcon ? rightIconBox.left : parent.right
        anchors.rightMargin: root.hasRightIcon ? root.iconGap : 0
        anchors.verticalCenter: parent.verticalCenter
        height: root.trackHeight

        // Unfilled background track (18% alpha textPrimary)
        Rectangle {
            anchors.fill: parent
            radius: parent.height / 2
            color: Services.ThemeService.textPrimary
            opacity: 0.18
        }

        // Filled track (full strength textPrimary or accentFill; 40% opacity when muted)
        Rectangle {
            id: fillRect
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.height / 2
            width: {
                if (track.width <= 0 || root.visualNorm <= 0) return 0;
                if (root.visualNorm >= 1.0) return track.width;
                return root.handleCenterX;
            }
            color: root.accentFill ? root.accentColor : Services.ThemeService.textPrimary
            opacity: root.muted ? 0.40 : 1.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // ═══════════════════════════════════════════
        // CAPSULE HANDLE (Visible on hover / drag)
        // ═══════════════════════════════════════════
        Rectangle {
            id: handle
            width: root.handleWidth
            height: root.handleHeight
            radius: root.handleRadius
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(track.width - width, root.visualNorm * root.trackAvail))

            color: root.accentColor
            border.color: Services.Aesthetic.innerCardBorder
            border.width: Services.Aesthetic.borderWidth

            opacity: root.handleActive ? 1.0 : 0.0
            scale: (root.isDragging || trackMouseArea.pressed) ? 1.06 : (root.handleActive ? 1.0 : 0.7)

            Behavior on opacity {
                NumberAnimation {
                    duration: root.handleActive ? 120 : 150
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // MOUSE INTERACTION (Full row height hit area)
    // ═══════════════════════════════════════════
    MouseArea {
        id: trackMouseArea
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: track.left
        anchors.right: track.right

        hoverEnabled: root.enabled
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onPressed: (mouse) => {
            root.isDragging = true;
            root.applyDrag(mouse.x);
        }

        onPositionChanged: (mouse) => {
            if (pressed || root.isDragging) {
                root.applyDrag(mouse.x);
            }
        }

        onReleased: (mouse) => {
            if (root.isDragging) {
                throttleTimer.stop();
                root.hasPendingMoved = false;
                root.isDragging = false;
                const finalVal = root.valueFromX(mouse.x);
                root.dragValue = finalVal;
                root.committed(finalVal);
            }
        }

        onCanceled: {
            throttleTimer.stop();
            root.hasPendingMoved = false;
            root.isDragging = false;
        }

        onWheel: (wheel) => {
            if (!root.enabled || root.isDragging) return;
            wheel.accepted = true;
            const step = (root.to - root.from) * 0.02;
            const deltaY = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            const dir = deltaY > 0 ? 1 : -1;
            const delta = root.stepSize > 0 ? Math.max(root.stepSize, step) : step;
            const newVal = Math.max(root.from, Math.min(root.to, root.value + dir * delta));
            root.committed(newVal);
            root.wheeled(newVal);
        }
    }
}
