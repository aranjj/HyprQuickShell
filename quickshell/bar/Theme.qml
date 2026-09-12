import QtQuick
import "../services" as Services

QtObject {
    // ── Dynamic Wallpaper-Derived Backgrounds (Matugen) ─────────────────
    readonly property bool barIsLight:   Services.ThemeService.barIsLight
    readonly property real barLum:       Services.ThemeService.barLum
    readonly property color barBg:       Services.ThemeService.barBg
    readonly property color pillBg:      Services.ThemeService.pillBg
    readonly property color pillHover:   Services.ThemeService.pillHover
    readonly property color pillActive:  Services.ThemeService.pillActive

    // ── Text & Content ────────────────────────────────────────
    readonly property color textPrimary:   Services.ThemeService.textPrimary
    readonly property color textSecondary: Services.ThemeService.textSecondary
    readonly property color textMuted:     Services.ThemeService.textMuted

    // ── Accents ─────────────────────────────────────
    readonly property color accent:       Services.ThemeService.accent
    readonly property color accentGreen:  Services.ThemeService.accentGreen
    readonly property color accentOrange: Services.ThemeService.accentOrange
    readonly property color accentRed:    Services.ThemeService.accentRed
    readonly property color accentYellow: Services.ThemeService.accentYellow
    readonly property color accentPink:   Services.ThemeService.accentPink
    readonly property color accentMauve:  Services.ThemeService.accentMauve

    // ── Material You Extended Palette ───────────────
    readonly property color primary:            Services.ThemeService.colPrimary
    readonly property color onPrimary:          Services.ThemeService.colOnPrimary
    readonly property color primaryContainer:   Services.ThemeService.colPrimaryContainer
    readonly property color secondary:          Services.ThemeService.colSecondary
    readonly property color secondaryContainer: Services.ThemeService.colSecondaryContainer
    readonly property color tertiary:           Services.ThemeService.colTertiary
    readonly property color tertiaryContainer:  Services.ThemeService.colTertiaryContainer
    readonly property color surface:            Services.ThemeService.colSurface
    readonly property color surfaceContainer:   Services.ThemeService.colSurfaceContainer
    readonly property color surfaceContainerHigh: Services.ThemeService.colSurfaceContainerHigh
    readonly property color surfaceDim:         Services.ThemeService.colSurfaceDim
    readonly property color outline:            Services.ThemeService.colOutline

    // ── Workspace ───────────────────────────────────
    readonly property color wsActive:   accent
    readonly property color wsOccupied: textSecondary
    readonly property color wsEmpty:    Services.ThemeService.wsEmpty

    // ── Battery ─────────────────────────────────────
    readonly property color battGood:     accentGreen
    readonly property color battWarn:     accentOrange
    readonly property color battCritical: accentRed

    // ── Font ────────────────────────────────────────
    readonly property string fontFamily: "Inter"
    readonly property int fontSize:      12
    readonly property int iconSize:      15
}
