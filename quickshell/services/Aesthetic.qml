pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as Services

Singleton {
    id: root

    readonly property string configFile: "/home/aran/.config/quickshell/aesthetic.json"

    // Presets: "frosted" | "oled" | "crystal" | "solid"
    property string preset: "frosted"

    // Master Design Tokens
    property int cardRadius: 18
    property int pillRadius: 13
    property int borderWidth: 1

    // ── Hardcoded Opacities & Design Tokens by Preset ────────
    readonly property real cardOpacity: {
        switch (preset) {
            case "oled": return 1.0;
            case "crystal": return 0.45;
            case "solid": return 0.96;
            case "frosted":
            default: return 0.68;
        }
    }

    readonly property real barFloatingOpacity: {
        switch (preset) {
            case "oled": return 1.0;
            case "crystal": return 0.22;
            case "solid": return 0.94;
            case "frosted":
            default: return 0.40;
        }
    }

    readonly property real borderOpacity: {
        switch (preset) {
            case "oled": return 0.12;
            case "crystal": return 0.32;
            case "solid": return 0.18;
            case "frosted":
            default: return 0.20;
        }
    }

    readonly property real backdropOpacity: {
        switch (preset) {
            case "oled": return 0.70;
            case "crystal": return 0.35;
            case "solid": return 0.65;
            case "frosted":
            default: return 0.45;
        }
    }

    // ── Inner Tile / Sub-Widget Glass Tokens ─────────
    readonly property real innerCardOpacity: {
        switch (preset) {
            case "oled": return 0.07;
            case "crystal": return 0.12;
            case "solid": return 0.75;
            case "frosted":
            default: return 0.26;
        }
    }

    readonly property real innerCardHoverOpacity: {
        switch (preset) {
            case "oled": return 0.14;
            case "crystal": return 0.20;
            case "solid": return 0.88;
            case "frosted":
            default: return 0.38;
        }
    }

    readonly property color innerCardBg: {
        if (preset === "oled") {
            return Qt.rgba(1, 1, 1, innerCardOpacity);
        }
        return Qt.rgba(
            Services.ThemeService.colSurfaceContainer.r,
            Services.ThemeService.colSurfaceContainer.g,
            Services.ThemeService.colSurfaceContainer.b,
            innerCardOpacity
        );
    }

    readonly property color innerCardHover: {
        if (preset === "oled") {
            return Qt.rgba(1, 1, 1, innerCardHoverOpacity);
        }
        return Qt.rgba(
            Services.ThemeService.colSurfaceContainerHigh.r,
            Services.ThemeService.colSurfaceContainerHigh.g,
            Services.ThemeService.colSurfaceContainerHigh.b,
            innerCardHoverOpacity
        );
    }

    readonly property color innerCardBorder: Qt.rgba(1, 1, 1, preset === "oled" ? 0.09 : (preset === "crystal" ? 0.08 : 0.06))

    // ── Slider Tokens (Soft Translucent Tahoe Design) ──
    readonly property color sliderTrackBg: {
        if (preset === "oled") return Qt.rgba(1, 1, 1, 0.10);
        return Qt.rgba(
            Services.ThemeService.colPrimary.r,
            Services.ThemeService.colPrimary.g,
            Services.ThemeService.colPrimary.b,
            preset === "crystal" ? 0.15 : 0.20
        );
    }
    readonly property color sliderFill: Services.ThemeService.accent
    readonly property color sliderOnFill: Services.ThemeService.colOnPrimary

    // ── Computed Card Colors ────────────────────────
    property color cardBg: {
        if (preset === "oled") {
            return "#000000";
        }
        return Qt.rgba(
            Services.ThemeService.colSurface.r,
            Services.ThemeService.colSurface.g,
            Services.ThemeService.colSurface.b,
            cardOpacity
        );
    }
    Behavior on cardBg { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    property color cardBorder: {
        if (preset === "oled") {
            return Qt.rgba(1, 1, 1, borderOpacity);
        }
        return Qt.rgba(
            Services.ThemeService.colOutline.r,
            Services.ThemeService.colOutline.g,
            Services.ThemeService.colOutline.b,
            borderOpacity
        );
    }
    Behavior on cardBorder { ColorAnimation { duration: 250 } }

    // ── Computed Top Bar Glass Color ────────────────
    function barGlassColor(isLight) {
        if (preset === "crystal") {
            return "transparent";
        }
        if (preset === "oled") {
            return "#000000";
        }
        if (preset === "solid") {
            return Qt.rgba(
                Services.ThemeService.colSurface.r,
                Services.ThemeService.colSurface.g,
                Services.ThemeService.colSurface.b,
                barFloatingOpacity
            );
        }
        if (isLight) {
            return Qt.rgba(1, 1, 1, 0.25);
        }
        return Qt.rgba(0.04, 0.04, 0.07, barFloatingOpacity);
    }

    // ── Computed Backdrop Dim Color ─────────────────
    readonly property color backdropColor: Qt.rgba(0, 0, 0, backdropOpacity)

    // ── Presets Catalog for UI ──────────────────────
    readonly property var presets: [
        { id: "frosted", name: "Frosted Glass", icon: "󰌷", desc: "macOS Tahoe Glass" },
        { id: "oled",    name: "OLED Pitch",   icon: "󰆦", desc: "Deep Black Hardware Style" },
        { id: "crystal", name: "Crystal Clear",icon: "󱡘", desc: "Vibrant Wallpaper Passthrough" },
        { id: "solid",   name: "Solid Minimal",icon: "󰤚", desc: "High Contrast Surface" }
    ]

    function setPreset(newPreset) {
        const valid = ["frosted", "oled", "crystal", "solid"];
        if (valid.indexOf(newPreset) !== -1) {
            preset = newPreset;
            saveConfig();
        }
    }

    function cyclePreset() {
        const list = ["frosted", "oled", "crystal", "solid"];
        const idx = list.indexOf(preset);
        const next = list[(idx + 1) % list.length];
        setPreset(next);
    }

    // ── IPC Handler ─────────────────────────────────
    IpcHandler {
        target: "aesthetic"

        function setPreset(p: string): void {
            root.setPreset(p);
        }

        function set(p: string): void {
            root.setPreset(p);
        }

        function setRadius(val: int): void {
            root.cardRadius = Math.max(0, Math.min(40, val));
            root.saveConfig();
        }

        function cycle(): void {
            root.cyclePreset();
        }

        function current(): string {
            return root.preset;
        }

        function opacity(): real {
            return root.cardOpacity;
        }
    }

    // ── Persistence: Save / Load ────────────────────
    Process {
        id: saveProc
        command: ["sh", "-c", ""]
    }

    function saveConfig() {
        const json = JSON.stringify({
            preset: root.preset,
            cardRadius: root.cardRadius
        });
        saveProc.command = ["sh", "-c", "printf '%s' '" + json + "' > '" + root.configFile + "'"];
        saveProc.running = true;
    }

    Process {
        id: loadProc
        command: ["cat", root.configFile]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    if (parsed.preset) root.preset = parsed.preset;
                    if (parsed.cardRadius !== undefined) root.cardRadius = parsed.cardRadius;
                } catch (e) {
                }
            }
        }
    }
}
