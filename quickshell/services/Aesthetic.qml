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

    // ── Dynamic Opacities & Tokens by Preset ────────
    readonly property real cardOpacity: {
        switch (preset) {
            case "oled": return 0.95;
            case "crystal": return 0.50;
            case "solid": return 0.96;
            case "frosted":
            default: return 0.78;
        }
    }

    readonly property real barFloatingOpacity: {
        switch (preset) {
            case "oled": return 0.88;
            case "crystal": return 0.22;
            case "solid": return 0.94;
            case "frosted":
            default: return 0.40;
        }
    }

    readonly property real borderOpacity: {
        switch (preset) {
            case "oled": return 0.14;
            case "crystal": return 0.32;
            case "solid": return 0.18;
            case "frosted":
            default: return 0.22;
        }
    }

    readonly property real backdropOpacity: {
        switch (preset) {
            case "oled": return 0.60;
            case "crystal": return 0.35;
            case "solid": return 0.65;
            case "frosted":
            default: return 0.45;
        }
    }

    // ── Computed Card Colors ────────────────────────
    property color cardBg: {
        if (preset === "oled") {
            return Qt.rgba(0.04, 0.04, 0.06, cardOpacity);
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
    function barGlassColor(hasTopWindow, isLight) {
        if (hasTopWindow) {
            return Qt.rgba(
                Services.ThemeService.colSurface.r,
                Services.ThemeService.colSurface.g,
                Services.ThemeService.colSurface.b,
                0.85
            );
        }
        if (preset === "oled") {
            return Qt.rgba(0.02, 0.02, 0.03, barFloatingOpacity);
        }
        if (isLight) {
            return Qt.rgba(1, 1, 1, preset === "crystal" ? 0.18 : 0.25);
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

        function set(p: string): void {
            root.setPreset(p);
        }

        function cycle(): void {
            root.cyclePreset();
        }

        function current(): string {
            return root.preset;
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
                    if (parsed.cardRadius) root.cardRadius = parsed.cardRadius;
                } catch (e) {
                    // Default to frosted if unparseable
                }
            }
        }
    }
}
