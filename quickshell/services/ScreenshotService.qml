pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool toolbarVisible: false
    property string lastScreenshotPath: ""
    property bool previewVisible: false
    property int delayTimer: 0
    property string captureMode: "region"

    // Preview auto-dismiss state
    property bool previewHovered: false
    property real previewProgress: 1.0

    // Pending capture (for GUI-delayed invocations)
    property string _pendingMode: ""
    property int _pendingDelay: 0

    // ── Preview Auto-Dismiss Timer ─────────────────────
    Timer {
        id: dismissTimer
        interval: 50
        running: root.previewVisible && !root.previewHovered
        repeat: true
        onTriggered: {
            root.previewProgress -= (50 / 6000.0);
            if (root.previewProgress <= 0) {
                root.dismissPreview();
            }
        }
    }

    // ── Delayed Capture Timer ──────────────────────────
    // When capture is triggered from a GUI overlay (Control Center
    // or Toolbar), we must wait for the layer-shell surface to fully
    // unmap and release the Wayland seat pointer grab before spawning
    // hyprshot/slurp. A QML Timer is more reliable than a bash sleep
    // because the event loop has already processed the overlay close.
    Timer {
        id: captureDelayTimer
        interval: 400
        repeat: false
        onTriggered: {
            root._runCapture(root._pendingMode, root._pendingDelay);
        }
    }

    // ── Dedicated Process ──────────────────────────────
    Process {
        id: captureProc
        command: ["sh", "-c", ""]
    }

    // ── Preview Functions ──────────────────────────────
    function showPreview(path) {
        lastScreenshotPath = path;
        previewProgress = 1.0;
        previewVisible = true;
    }

    function dismissPreview() {
        previewVisible = false;
        previewProgress = 1.0;
    }

    // ── Toolbar Toggle ─────────────────────────────────
    function toggleToolbar() {
        toolbarVisible = !toolbarVisible;
    }

    // ── Post-Capture Actions ───────────────────────────
    function openLastScreenshot() {
        if (!lastScreenshotPath) return;
        captureProc.running = false;
        captureProc.command = ["sh", "-c",
            "spectacle -E '" + lastScreenshotPath + "' 2>/dev/null || " +
            "gwenview '" + lastScreenshotPath + "' 2>/dev/null || " +
            "xdg-open '" + lastScreenshotPath + "'"
        ];
        captureProc.running = true;
        dismissPreview();
    }

    function openScreenshotsFolder() {
        if (!lastScreenshotPath) return;
        captureProc.running = false;
        captureProc.command = ["sh", "-c",
            "dolphin --select '" + lastScreenshotPath + "' 2>/dev/null || " +
            "xdg-open /home/aran/Pictures/Screenshots"
        ];
        captureProc.running = true;
        dismissPreview();
    }

    function copyLastToClipboard() {
        if (!lastScreenshotPath) return;
        captureProc.running = false;
        captureProc.command = ["sh", "-c", "wl-copy --type image/png < '" + lastScreenshotPath + "'"];
        captureProc.running = true;
    }

    function deleteLastScreenshot() {
        if (!lastScreenshotPath) return;
        captureProc.running = false;
        captureProc.command = ["sh", "-c",
            "gio trash '" + lastScreenshotPath + "' 2>/dev/null || " +
            "rm -f '" + lastScreenshotPath + "'"
        ];
        captureProc.running = true;
        dismissPreview();
    }

    // ── Public Capture API ─────────────────────────────
    // Called by toolbar buttons, Control Center buttons, and IPC.
    // Detects whether a GUI overlay is open and, if so, delays the
    // capture to let the overlay unmap and release pointer grabs.
    function capture(mode, delaySecs) {
        const overlayWasOpen = toolbarVisible || SystemService.controlCenterOpen;

        toolbarVisible = false;
        SystemService.controlCenterOpen = false;

        const d = (delaySecs !== undefined && delaySecs > 0) ? delaySecs : 0;
        const m = mode || "region";

        if (overlayWasOpen && m !== "fullscreen") {
            // Delay: let the overlay surface fully unmap
            root._pendingMode = m;
            root._pendingDelay = d;
            captureDelayTimer.restart();
        } else {
            // Keyboard shortcut or fullscreen — execute immediately
            _runCapture(m, d);
        }
    }

    // ── Internal: Execute Capture ──────────────────────
    function _runCapture(mode, delaySecs) {
        captureProc.running = false;
        captureProc.command = [
            "/home/aran/.config/quickshell/scripts/screenshot.sh",
            mode,
            delaySecs.toString()
        ];
        captureProc.running = true;
    }

    // ── CLI / Keybinding IPC Interface ─────────────────
    IpcHandler {
        target: "screenshot"

        function preview(path: string): void {
            root.showPreview(path);
        }

        function full(): void {
            root.capture("fullscreen", 0);
        }

        function region(): void {
            root.capture("region", 0);
        }

        function window(): void {
            root.capture("window", 0);
        }

        function toolbar(): void {
            root.toggleToolbar();
        }

        function toggle(): void {
            root.toggleToolbar();
        }
    }
}
