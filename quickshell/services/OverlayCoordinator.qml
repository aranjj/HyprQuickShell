pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    // =========================================================================
    // EXPLICIT OVERLAY CLASSIFICATION ARCHITECTURE
    // =========================================================================
    // Class 1: Exclusive Interactive Surfaces (Mutually Exclusive Stack)
    //   Only ONE surface from this class may be active at any given moment.
    //   Opening any Class 1 surface automatically dismisses whichever Class 1
    //   surface was previously active, preventing unintended layer stacking.
    //   - "launcher"        : AppLauncher.qml
    //   - "controlCenter"   : ControlCenter.qml
    //   - "wallpaperPicker" : WallpaperPicker.qml
    //   - "clipboard"       : Clipboard.qml
    //   - "emojiPicker"     : EmojiPicker.qml
    //   - "powerMenu"       : PowerMenu.qml
    //   - "aboutDialog"     : AboutDialog.qml
    //   - "calendar"        : CalendarView.qml
    //
    // Class 2: Transient / Modal Overlays (Non-exclusive, coexisting or above shell)
    //   These overlays do NOT belong to the mutually exclusive interactive stack.
    //   - "screenshotToolbar" : ScreenshotToolbar.qml (workflow overlay; suspends & restores)
    //   - "screenshotPreview" : ScreenshotPreview.qml (transient bottom-right thumbnail)
    //   - "osd"               : OSD.qml (dynamic HUD in Dynamic Island)
    //   - "dynamicIsland"     : DynamicIsland.qml (ambient top status/media pill)
    //
    // Class 3: Persistent Shell Surfaces
    //   - "bar"               : Bar.qml (WlrLayer.Top, reserves space)
    //   - "wallpaper"         : Wallpaper.qml (WlrLayer.Background)
    //
    // Class 4: Session Security Layer
    //   - "lockScreen"        : LockScreen.qml (WlSessionLock protocol)
    // =========================================================================

    // Currently active exclusive surface identifier ("" when none is active)
    property string activeExclusiveSurface: ""

    // Timestamp (epoch ms) of when the last exclusive surface was closed or unmapped
    property double lastSurfaceClosedTime: 0

    // Suspended shell state for workflow overlays (e.g. Screenshot capture & restore)
    property string suspendedExclusiveSurface: ""

    // Registry of registered exclusive surfaces: { name: { open: Function, close: Function } }
    property var _surfaces: ({})

    // Register an exclusive surface with its open and close callbacks
    function registerExclusiveSurface(name, openFn, closeFn) {
        _surfaces[name] = { open: openFn, close: closeFn };
    }

    // Request exclusive interactive access for a Class 1 surface.
    // Gracefully dismisses ONLY the currently active equivalent exclusive surface.
    function requestExclusiveSurface(name) {
        if (activeExclusiveSurface === name) return;

        if (activeExclusiveSurface !== "") {
            const prev = activeExclusiveSurface;
            activeExclusiveSurface = "";
            lastSurfaceClosedTime = Date.now();
            const entry = _surfaces[prev];
            if (entry && typeof entry.close === "function") {
                try {
                    entry.close();
                } catch (err) {
                    console.warn("[OverlayCoordinator] Error closing", prev, ":", err);
                }
            }
        }

        activeExclusiveSurface = name;
    }

    // Release exclusive access when a Class 1 surface is closed/dismissed
    function releaseExclusiveSurface(name) {
        if (activeExclusiveSurface === name) {
            activeExclusiveSurface = "";
            lastSurfaceClosedTime = Date.now();
        }
    }

    // Close whichever exclusive surface is currently active
    function closeCurrentExclusiveSurface() {
        if (activeExclusiveSurface !== "") {
            const prev = activeExclusiveSurface;
            activeExclusiveSurface = "";
            lastSurfaceClosedTime = Date.now();
            const entry = _surfaces[prev];
            if (entry && typeof entry.close === "function") {
                try {
                    entry.close();
                } catch (err) {
                    console.warn("[OverlayCoordinator] Error closing", prev, ":", err);
                }
            }
        }
    }

    // Check if an exclusive surface is currently active
    function hasActiveExclusiveSurface() {
        return activeExclusiveSurface !== "";
    }

    // ── Workflow Overlay Suspension & Restoration ──────────────────────────
    // Temporarily suspends the active exclusive surface so workflow tools like
    // Screenshot can cleanly unmap shell surfaces before display freeze / capture.
    function suspendExclusiveSurface() {
        suspendedExclusiveSurface = activeExclusiveSurface;
        if (activeExclusiveSurface !== "") {
            lastSurfaceClosedTime = Date.now();
            closeCurrentExclusiveSurface();
        }
        return suspendedExclusiveSurface;
    }

    // Restores the previously active exclusive surface once the workflow completes.
    function restoreExclusiveSurface() {
        if (suspendedExclusiveSurface !== "") {
            const toRestore = suspendedExclusiveSurface;
            suspendedExclusiveSurface = "";
            const entry = _surfaces[toRestore];
            if (entry && typeof entry.open === "function") {
                requestExclusiveSurface(toRestore);
                try {
                    entry.open();
                } catch (err) {
                    console.warn("[OverlayCoordinator] Error restoring", toRestore, ":", err);
                }
            }
        }
    }
}
