pragma Singleton

import Quickshell
import QtQuick
import "." as Services

Singleton {
    id: root

    property bool visible: false
    property string icon: "󰕾"
    property color iconColor: Services.ThemeService.accent
    property string title: "Volume"
    property string valueText: "50%"
    property real progress: 0.5 // 0.0 to 1.0, or -1 to hide progress bar
    property color barColor: Services.ThemeService.accent

    function show(iconStr, iconCol, titleStr, textStr, progressVal, barCol) {
        icon = iconStr;
        iconColor = iconCol || Services.ThemeService.accent;
        title = titleStr;
        valueText = textStr;
        progress = progressVal;
        barColor = barCol || iconCol || Services.ThemeService.accent;
        visible = true;
        hideTimer.restart();
    }

    signal volumeUpdated(int vol, bool muted)
    signal brightnessUpdated(int pct)

    function showVolume(vol, muted) {
        const isHp = Services.SystemService.isHeadphones;
        const ic = muted ? (isHp ? "󰟎" : "󰖁") : (isHp ? "󰋋" : (vol > 60 ? "󰕾" : (vol > 20 ? "󰖀" : "󰕿")));
        const col = muted ? Services.ThemeService.accentRed : Services.ThemeService.accent;
        const titleText = isHp ? "Headphones" : "Volume";
        show(ic, col, titleText, muted ? "Muted" : vol + "%", muted ? 0 : Math.min(1.0, vol / 100), col);
        volumeUpdated(vol, muted);
    }

    function showMic(vol, muted) {
        const ic = muted ? "󰍭" : "󰍬";
        const col = muted ? Services.ThemeService.accentRed : Services.ThemeService.accent;
        show(ic, col, "Microphone", muted ? "Muted" : vol + "%", muted ? 0 : Math.min(1.0, vol / 100), col);
    }

    property bool suppressBrightness: false

    function showBrightness(pct) {
        if (suppressBrightness) return;
        const ic = pct > 70 ? "󰃠" : (pct > 30 ? "󰃟" : "󰃞");
        const col = Services.ThemeService.accentYellow;
        show(ic, col, "Brightness", pct + "%", Math.min(1.0, pct / 100), col);
        brightnessUpdated(pct);
    }

    function showPowerProfile(profile) {
        let ic = "󰾅";
        let col = Services.ThemeService.accent;
        let name = "Balanced";
        if (profile === "performance") {
            ic = "󰓅";
            col = Services.ThemeService.accentOrange;
            name = "Performance";
        } else if (profile === "power-saver") {
            ic = "󰌪";
            col = Services.ThemeService.accentGreen;
            name = "Power Saver";
        }
        show(ic, col, "Power Profile", name, -1, col);
    }

    function showPowerSupply(plugged, level) {
        const ic = plugged ? "󰂄" : "󰁹";
        const col = plugged ? Services.ThemeService.accentGreen : Services.ThemeService.accent;
        const text = plugged ? "Plugged In (" + level + "%)" : "On Battery (" + level + "%)";
        show(ic, col, "Power Source", text, Math.min(1.0, level / 100), col);
    }

    Timer {
        id: hideTimer
        interval: 1400
        onTriggered: root.visible = false
    }
}
