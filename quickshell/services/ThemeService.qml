pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string colorsFile: "/home/aran/.config/quickshell/theme/colors.json"
    readonly property string matugenScript: "/home/aran/.config/quickshell/scripts/matugen.sh"

    // ── Material You Core Colors (with smooth cubic morphing) ──
    property color colPrimary: "#89b4fa"
    Behavior on colPrimary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnPrimary: "#00344a"
    Behavior on colOnPrimary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colPrimaryContainer: "#004c6a"
    Behavior on colPrimaryContainer { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnPrimaryContainer: "#c5e7ff"
    Behavior on colOnPrimaryContainer { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSecondary: "#b6c9d8"
    Behavior on colSecondary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnSecondary: "#20333e"
    Behavior on colOnSecondary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSecondaryContainer: "#374955"
    Behavior on colSecondaryContainer { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colTertiary: "#cba6f7"
    Behavior on colTertiary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnTertiary: "#332c4c"
    Behavior on colOnTertiary { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colTertiaryContainer: "#494263"
    Behavior on colTertiaryContainer { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurface: "#0f1417"
    Behavior on colSurface { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurfaceDim: "#0f1417"
    Behavior on colSurfaceDim { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurfaceBright: "#353a3d"
    Behavior on colSurfaceBright { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurfaceContainer: "#1c2023"
    Behavior on colSurfaceContainer { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurfaceContainerHigh: "#262b2e"
    Behavior on colSurfaceContainerHigh { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colSurfaceContainerHighest: "#313539"
    Behavior on colSurfaceContainerHighest { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnSurface: "#dfe3e7"
    Behavior on colOnSurface { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOnSurfaceVariant: "#c1c7ce"
    Behavior on colOnSurfaceVariant { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOutline: "#8b9297"
    Behavior on colOutline { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colOutlineVariant: "#41484d"
    Behavior on colOutlineVariant { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    property color colError: "#ffb4ab"
    Behavior on colError { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // ── High-level Shell Semantic Tokens ──
    property color accent: colPrimary
    property color accentSecondary: colSecondary
    property color accentTertiary: colTertiary
    property color accentMauve: colTertiary
    property color accentGreen: "#30d158"
    property color accentOrange: "#ff9f0a"
    property color accentRed: colError
    property color accentYellow: "#ffd60a"
    property color accentPink: "#ff375f"

    // ── Adaptive Bar Luminance (macOS Tahoe style) ────
    property bool barIsLight: false
    property real barLum: 0.0

    property color barBg: Qt.rgba(colSurface.r, colSurface.g, colSurface.b, 0.78)
    property color pillBg: Qt.rgba(colSurfaceContainerHigh.r, colSurfaceContainerHigh.g, colSurfaceContainerHigh.b, 0.65)
    property color pillHover: Qt.rgba(colPrimary.r, colPrimary.g, colPrimary.b, 0.18)
    property color pillActive: colPrimary

    property color textPrimary: colOnSurface
    property color textSecondary: Qt.rgba(colOnSurfaceVariant.r, colOnSurfaceVariant.g, colOnSurfaceVariant.b, 0.92)
    property color textMuted: Qt.rgba(colOnSurfaceVariant.r, colOnSurfaceVariant.g, colOnSurfaceVariant.b, 0.75)

    property color wsActive: colPrimary
    property color wsOccupied: colOnSurfaceVariant
    property color wsEmpty: Qt.rgba(colOutline.r, colOutline.g, colOutline.b, 0.25)

    property color battGood: accentGreen
    property color battWarn: accentOrange
    property color battCritical: accentRed

    // ── Actions ────────────────────────────────────────
    function generateFromWallpaper(path) {
        if (!path || path.length === 0) return;
        const clean = path.replace(/^file:\/\//, "");
        matugenProc.command = [matugenScript, clean];
        matugenProc.running = true;
    }

    function loadColors() {
        readProc.command = ["cat", colorsFile];
        readProc.running = true;
    }

    // ── Process: Matugen Generator ──────────────────────
    Process {
        id: matugenProc
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.loadColors();
            }
        }
    }

    // ── Process: Load and parse colors.json ─────────────
    Process {
        id: readProc
        command: ["cat", root.colorsFile]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim().length === 0) return;
                try {
                    const data = JSON.parse(text);
                    if (data.primary) root.colPrimary = data.primary;
                    if (data.on_primary) root.colOnPrimary = data.on_primary;
                    if (data.primary_container) root.colPrimaryContainer = data.primary_container;
                    if (data.on_primary_container) root.colOnPrimaryContainer = data.on_primary_container;
                    if (data.secondary) root.colSecondary = data.secondary;
                    if (data.on_secondary) root.colOnSecondary = data.on_secondary;
                    if (data.secondary_container) root.colSecondaryContainer = data.secondary_container;
                    if (data.tertiary) root.colTertiary = data.tertiary;
                    if (data.on_tertiary) root.colOnTertiary = data.on_tertiary;
                    if (data.tertiary_container) root.colTertiaryContainer = data.tertiary_container;
                    if (data.surface) root.colSurface = data.surface;
                    if (data.surface_dim) root.colSurfaceDim = data.surface_dim;
                    if (data.surface_bright) root.colSurfaceBright = data.surface_bright;
                    if (data.surface_container) root.colSurfaceContainer = data.surface_container;
                    if (data.surface_container_high) root.colSurfaceContainerHigh = data.surface_container_high;
                    if (data.surface_container_highest) root.colSurfaceContainerHighest = data.surface_container_highest;
                    if (data.on_surface) root.colOnSurface = data.on_surface;
                    if (data.on_surface_variant) root.colOnSurfaceVariant = data.on_surface_variant;
                    if (data.outline) root.colOutline = data.outline;
                    if (data.outline_variant) root.colOutlineVariant = data.outline_variant;
                    if (data.error) root.colError = data.error;
                    if (data.bar_is_light !== undefined) root.barIsLight = !!data.bar_is_light;
                    if (data.bar_lum !== undefined) root.barLum = data.bar_lum;
                } catch (e) {
                    // ignore JSON parse errors during write
                }
            }
        }
    }

    // ── IPC Interface ──────────────────────────────────
    IpcHandler {
        target: "theme"
        function reload() { root.loadColors(); }
        function generate(path: string) { root.generateFromWallpaper(path); }
    }
}
