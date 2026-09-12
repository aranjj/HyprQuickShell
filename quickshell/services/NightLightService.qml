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
        execProc.command = ["sh", "-c", "export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}; " + cmd];
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
        runCmd("pkill -x hyprsunset 2>/dev/null; /home/aran/.local/bin/hyprsunset -t 3000 >/dev/null 2>&1 &");
    }

    function disable() {
        root.active = false;
        runCmd("pkill -x hyprsunset 2>/dev/null");
    }

    Component.onCompleted: {
        statusProc.running = true;
    }
}
