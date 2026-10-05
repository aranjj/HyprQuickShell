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

    // "large" (~32px) | "medium" (~22px) | "thin" (4->8px track)
    property string size: "large"
    property string icon: ""
    property bool muted: false
    property bool enabled: true
    property bool iconClickable: false

    property color accentColor: Services.ThemeService.accent
    property color onAccentColor: Services.ThemeService.colOnPrimary
    property string font: "Inter, MesloLGM Nerd Font, sans-serif"

    signal iconClicked()
    signal moved(real value)
    signal committed(real value)
    signal wheeled(real value)

    // ── Internal State ──
    property bool isDragging: false
    property real dragValue: value
    property bool hasPendingMoved: false
    property bool startedInIcon: false
    property real pressStartX: 0

    readonly property real displayValue: isDragging ? dragValue : value

    readonly property real norm: {
        const span = to - from;
        if (span <= 0) return 0.0;
        const v = isDragging ? dragValue : value;
        return Math.max(0.0, Math.min(1.0, (v - from) / span));
    }

    implicitWidth: 200
    implicitHeight: {
        if (size === "medium") return 22;
        if (size === "thin") return 18;
        return 32; // "large"
    }

    opacity: enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: 150 } }

    activeFocusOnTab: enabled

    // Helpers
    function valueFromX(mouseX) {
        const span = to - from;
        if (width <= 0 || span <= 0) return from;
        const ratio = Math.max(0.0, Math.min(1.0, mouseX / width));
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
    // LARGE & MEDIUM SLIDER VISUALS
    // ═══════════════════════════════════════════
    Rectangle {
        id: pillTrack
        visible: root.size !== "thin"
        anchors.fill: parent
        radius: height / 2
        color: Services.Aesthetic.sliderTrackBg
        border.color: mouseArea.containsMouse ? Services.Aesthetic.innerCardHover : Services.Aesthetic.innerCardBorder
        border.width: Services.Aesthetic.borderWidth
        clip: true

        Behavior on border.color { ColorAnimation { duration: 120 } }

        // Dynamic Fill Capsule (Pill)
        Rectangle {
            id: pillFill
            height: parent.height
            radius: parent.radius
            width: {
                if (parent.width <= 0) return 0;
                return Math.max(parent.height, Math.min(parent.width, parent.width * root.norm));
            }
            color: {
                if (root.muted) return Services.Aesthetic.innerCardHover;
                if (mouseArea.containsMouse || root.isDragging) return Qt.lighter(root.accentColor, 1.08);
                return root.accentColor;
            }
            clip: true

            Behavior on width {
                enabled: !root.isDragging && !mouseArea.pressed
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 140 } }

            // Icon sits inside the left end of the fill
            Item {
                id: iconContainer
                width: parent.height
                height: parent.height
                anchors.left: parent.left
                anchors.top: parent.top
                visible: root.icon !== ""

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: root.muted ? Services.ThemeService.textMuted : root.onAccentColor
                    font.pixelSize: root.size === "medium" ? 11 : 15
                    font.family: root.font
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }
    }

    // ═══════════════════════════════════════════
    // THIN SLIDER VISUALS (MEDIA PROGRESS / SEEK)
    // ═══════════════════════════════════════════
    Rectangle {
        id: thinTrack
        visible: root.size === "thin"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: (mouseArea.containsMouse || root.isDragging) ? 8 : 4
        radius: height / 2
        color: Services.Aesthetic.sliderTrackBg
        border.color: Services.Aesthetic.innerCardBorder
        border.width: Services.Aesthetic.borderWidth
        clip: true

        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // Filled progress bar
        Rectangle {
            id: thinFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            width: Math.max(0, Math.min(parent.width, parent.width * root.norm))
            color: (mouseArea.containsMouse || root.isDragging) ? Qt.lighter(root.accentColor, 1.08) : root.accentColor

            Behavior on width {
                enabled: !root.isDragging && !mouseArea.pressed
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    // Knob for Thin Slider (Circular thumb handle)
    Rectangle {
        id: thinKnob
        visible: root.size === "thin"
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: 6
        color: root.accentColor
        border.color: Services.Aesthetic.innerCardBorder
        border.width: 1
        x: Math.max(0, Math.min(parent.width - width, (parent.width * root.norm) - (width / 2)))
        opacity: (mouseArea.containsMouse || root.isDragging) ? 1.0 : 0.0

        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on x {
            enabled: !root.isDragging && !mouseArea.pressed
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    // ═══════════════════════════════════════════
    // MOUSE INTERACTION (ALL VARIANTS)
    // ═══════════════════════════════════════════
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.enabled
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onPressed: (mouse) => {
            root.pressStartX = mouse.x;
            const iconHitWidth = (root.size === "large" ? 36 : 26);
            root.startedInIcon = root.iconClickable && (mouse.x <= iconHitWidth);
            if (!root.startedInIcon) {
                root.isDragging = true;
                root.applyDrag(mouse.x);
            }
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                const iconHitWidth = (root.size === "large" ? 36 : 26);
                const dx = Math.abs(mouse.x - root.pressStartX);
                if (root.startedInIcon && (dx > 4 || mouse.x > iconHitWidth)) {
                    root.startedInIcon = false;
                    root.isDragging = true;
                }
                if (root.isDragging) {
                    root.applyDrag(mouse.x);
                }
            }
        }

        onReleased: (mouse) => {
            if (root.startedInIcon && Math.abs(mouse.x - root.pressStartX) <= 4) {
                root.iconClicked();
            } else if (root.isDragging) {
                throttleTimer.stop();
                root.hasPendingMoved = false;
                root.isDragging = false;
                const finalVal = root.valueFromX(mouse.x);
                root.dragValue = finalVal;
                root.committed(finalVal);
            }
            root.startedInIcon = false;
            root.isDragging = false;
        }

        onCanceled: {
            throttleTimer.stop();
            root.hasPendingMoved = false;
            root.isDragging = false;
            root.startedInIcon = false;
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
