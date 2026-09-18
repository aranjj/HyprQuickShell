pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as Services

Singleton {
    id: root

    property bool toolbarVisible: false
    property string lastScreenshotPath: ""
    property bool previewVisible: false
    property int delayTimer: 0
    property string captureMode: "region"

    // Freeze-frame state
    property string freezeImagePath: ""
    property int freezeVersion: 0
    property bool isSelecting: false
    property bool isFreezing: false
    property bool directSnipMode: false
    property string _pendingDirectMode: ""

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
    Timer {
        id: captureDelayTimer
        interval: 400
        repeat: false
        onTriggered: {
            root._runCapture(root._pendingMode, root._pendingDelay);
        }
    }

    // ── Control Center Unmap Delay for Freeze ──────────
    Timer {
        id: ccUnmapTimer
        interval: 120
        repeat: false
        onTriggered: root._startFreeze()
    }

    // ── Dedicated Process for Hyprland Dispatch ────────
    Process {
        id: dispatchProc
        command: ["sh", "-c", ""]
    }

    function _runCommand(cmd) {
        dispatchProc.running = false;
        dispatchProc.command = ["hyprctl", "dispatch", "hl.dsp.exec_cmd(\"" + cmd.replace(/"/g, '\\"') + "\")"];
        dispatchProc.running = true;
    }

    // ── Kill Slurp Process ─────────────────────────────
    Process {
        id: killSlurpProc
        command: ["pkill", "-x", "slurp"]
    }

    // ── Freeze Process ─────────────────────────────────
    // Takes a snapshot at the exact millisecond toolbar or snip is requested
    Process {
        id: freezeProc
        command: ["grim", "-l", "1", "/tmp/quickshell_freeze.png"]
        onExited: (code, status) => {
            root.isFreezing = false;
            if (code === 0) {
                root.freezeVersion++;
                root.freezeImagePath = "/tmp/quickshell_freeze.png";
                root.toolbarVisible = true;
                if (root.directSnipMode) {
                    const m = (root._pendingDirectMode === "window") ? "window_frozen" : "region_frozen";
                    root._runCommand("/home/aran/.config/quickshell/scripts/screenshot.sh " + m + " 0 /tmp/quickshell_freeze.png");
                }
            } else {
                root.freezeImagePath = "";
                const wasDirect = root.directSnipMode;
                const pendingMode = root._pendingDirectMode;
                root.closeToolbar();
                if (wasDirect) {
                    root._runCapture(pendingMode === "window" ? "window" : "region", 0);
                }
            }
        }
    }

    function _startFreeze() {
        root.isFreezing = true;
        freezeProc.running = false;
        freezeProc.command = ["grim", "-l", "1", "/tmp/quickshell_freeze.png"];
        freezeProc.running = true;
    }

    function startDirectSnip(mode) {
        if (root.isFreezing) return;
        const m = (mode === "window") ? "window" : "region";

        // If toolbar is already open with a valid freeze frame, snip immediately from it
        if (root.toolbarVisible && root.freezeImagePath !== "") {
            root.isSelecting = true;
            _runCommand("/home/aran/.config/quickshell/scripts/screenshot.sh " + m + "_frozen 0 /tmp/quickshell_freeze.png");
            return;
        }

        root.directSnipMode = true;
        root.isSelecting = true;
        root._pendingDirectMode = m;

        if (Services.SystemService.controlCenterOpen) {
            Services.SystemService.controlCenterOpen = false;
            ccUnmapTimer.restart();
            return;
        }

        _startFreeze();
    }

    function openToolbar() {
        if (root.toolbarVisible) return;
        root.directSnipMode = false;
        root.isSelecting = false;
        if (Services.SystemService.controlCenterOpen) {
            Services.SystemService.controlCenterOpen = false;
            ccUnmapTimer.restart();
            return;
        }
        _startFreeze();
    }

    function closeToolbar() {
        toolbarVisible = false;
        isSelecting = false;
        directSnipMode = false;
        _pendingDirectMode = "";
        freezeImagePath = "";
        killSlurpProc.running = false;
        killSlurpProc.running = true;
    }

    // ── Toolbar Toggle ─────────────────────────────────
    function toggleToolbar() {
        if (toolbarVisible) {
            closeToolbar();
        } else {
            openToolbar();
        }
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

    // ── Post-Capture Actions ───────────────────────────
    function openLastScreenshot() {
        if (!lastScreenshotPath) return;
        _runCommand(
            "spectacle -E '" + lastScreenshotPath + "' 2>/dev/null || " +
            "gwenview '" + lastScreenshotPath + "' 2>/dev/null || " +
            "xdg-open '" + lastScreenshotPath + "'"
        );
        dismissPreview();
    }

    function openScreenshotsFolder() {
        if (!lastScreenshotPath) return;
        _runCommand(
            "dolphin --select '" + lastScreenshotPath + "' 2>/dev/null || " +
            "xdg-open /home/aran/Pictures/Screenshots"
        );
        dismissPreview();
    }

    function copyLastToClipboard() {
        if (!lastScreenshotPath) return;
        _runCommand("wl-copy --type image/png < '" + lastScreenshotPath + "'");
    }

    function deleteLastScreenshot() {
        if (!lastScreenshotPath) return;
        _runCommand(
            "gio trash '" + lastScreenshotPath + "' 2>/dev/null || " +
            "rm -f '" + lastScreenshotPath + "'"
        );
        dismissPreview();
    }

    // ── Public Capture API ─────────────────────────────
    function capture(mode, delaySecs) {
        const d = (delaySecs !== undefined && delaySecs > 0) ? delaySecs : 0;
        const m = mode || root.captureMode || "region";

        if (d > 0) {
            // User requested delayed capture: close overlay, let user set up screen, then capture
            closeToolbar();
            Services.SystemService.controlCenterOpen = false;
            root._pendingMode = m;
            root._pendingDelay = d;
            captureDelayTimer.restart();
            return;
        }

        // Instant freeze-frame capture from toolbar:
        if (root.toolbarVisible && root.freezeImagePath !== "") {
            if (m === "fullscreen") {
                closeToolbar();
                _runCommand("/home/aran/.config/quickshell/scripts/screenshot.sh save_frozen 0 /tmp/quickshell_freeze.png");
            } else if (m === "window") {
                root.isSelecting = true;
                _runCommand("/home/aran/.config/quickshell/scripts/screenshot.sh window_frozen 0 /tmp/quickshell_freeze.png");
            } else {
                // region
                root.isSelecting = true;
                _runCommand("/home/aran/.config/quickshell/scripts/screenshot.sh region_frozen 0 /tmp/quickshell_freeze.png");
            }
            return;
        }

        // Direct shortcut or background invocation
        if (m === "fullscreen") {
            const overlayWasOpen = toolbarVisible || Services.SystemService.controlCenterOpen;
            closeToolbar();
            Services.SystemService.controlCenterOpen = false;

            if (overlayWasOpen) {
                root._pendingMode = m;
                root._pendingDelay = d;
                captureDelayTimer.restart();
            } else {
                _runCapture(m, d);
            }
        } else {
            startDirectSnip(m);
        }
    }

    // ── Internal: Execute Capture ──────────────────────
    function _runCapture(mode, delaySecs) {
        const cmd = "/home/aran/.config/quickshell/scripts/screenshot.sh " + mode + " " + delaySecs;
        _runCommand(cmd);
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
            root.startDirectSnip("region");
        }

        function window(): void {
            root.startDirectSnip("window");
        }

        function snipRegion(): void {
            root.startDirectSnip("region");
        }

        function snipWindow(): void {
            root.startDirectSnip("window");
        }

        function toolbar(): void {
            root.toggleToolbar();
        }

        function toggle(): void {
            root.toggleToolbar();
        }

        function close(): void {
            root.closeToolbar();
        }

        function closeToolbar(): void {
            root.closeToolbar();
        }
    }
}
