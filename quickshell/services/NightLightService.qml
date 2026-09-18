pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool active: false
    readonly property int temperature: 3000

    // ── CLI / Keybinding IPC Interface ─────────────────
    IpcHandler {
        target: "nightlight"

        function toggle(): void {
            root.toggle();
        }

        function enable(): void {
            root.enable();
        }

        function disable(): void {
            root.disable();
        }

        function isActive(): bool {
            return root.active;
        }
    }

    // ── Check if hyprsunset process is running ─────────
    Process {
        id: statusProc
        command: ["sh", "-c", "pgrep -x hyprsunset >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.active = (text.trim() === "1");
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            if (!statusProc.running) statusProc.running = true;
        }
    }

    Process {
        id: execProc
        command: ["sh", "-c", ""]
    }

    function runCmd(cmd) {
        execProc.running = false;
        execProc.command = ["sh", "-c", "[ -z \"$WAYLAND_DISPLAY\" ] && export WAYLAND_DISPLAY=$(ls -1 \"$XDG_RUNTIME_DIR\"/wayland-[0-9]* 2>/dev/null | head -n 1 | xargs -r basename || echo wayland-0); " + cmd];
        execProc.running = true;
    }

    function toggle() {
        if (root.active) {
            disable();
        } else {
            enable();
        }
    }

    function enable() {
        root.active = true;
        runCmd("pkill -x hyprsunset 2>/dev/null; sleep 0.1; hyprsunset --temperature " + root.temperature + " >/dev/null 2>&1 &");
    }

    function disable() {
        root.active = false;
        runCmd("pkill -x hyprsunset 2>/dev/null");
    }

    Component.onCompleted: {
        statusProc.running = true;
    }
}
