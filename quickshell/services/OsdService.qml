pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    property bool visible: false
    property string icon: "󰕾"
    property color iconColor: "#89b4fa"
    property string title: "Volume"
    property string valueText: "50%"
    property real progress: 0.5 // 0.0 to 1.0, or -1 to hide progress bar
    property color barColor: "#89b4fa"

    function show(iconStr, iconCol, titleStr, textStr, progressVal, barCol) {
        icon = iconStr;
        iconColor = iconCol;
        title = titleStr;
        valueText = textStr;
        progress = progressVal;
        barColor = barCol || iconCol;
        visible = true;
        hideTimer.restart();
    }

    signal volumeUpdated(int vol, bool muted)
    signal brightnessUpdated(int pct)

    function showVolume(vol, muted) {
        const ic = muted ? "󰖁" : (vol > 60 ? "󰕾" : (vol > 20 ? "󰖀" : "󰕿"));
        const col = muted ? "#f38ba8" : "#89b4fa";
        show(ic, col, "Volume", muted ? "Muted" : vol + "%", muted ? 0 : Math.min(1.0, vol / 100), col);
        volumeUpdated(vol, muted);
    }

    function showMic(vol, muted) {
        const ic = muted ? "󰍭" : "󰍬";
        const col = muted ? "#f38ba8" : "#89b4fa";
        show(ic, col, "Microphone", muted ? "Muted" : vol + "%", muted ? 0 : Math.min(1.0, vol / 100), col);
    }

    property bool suppressBrightness: false

    function showBrightness(pct) {
        if (suppressBrightness) return;
        const ic = pct > 70 ? "󰃠" : (pct > 30 ? "󰃟" : "󰃞");
        show(ic, "#f9e2af", "Brightness", pct + "%", Math.min(1.0, pct / 100), "#f9e2af");
        brightnessUpdated(pct);
    }

    function showPowerProfile(profile) {
        let ic = "󰾅";
        let col = "#89b4fa";
        let name = "Balanced";
        if (profile === "performance") {
            ic = "󰓅";
            col = "#fab387";
            name = "Performance";
        } else if (profile === "power-saver") {
            ic = "󰌪";
            col = "#a6e3a1";
            name = "Power Saver";
        }
        show(ic, col, "Power Profile", name, -1, col);
    }

    function showPowerSupply(plugged, level) {
        const ic = plugged ? "󰂄" : "󰁹";
        const col = plugged ? "#a6e3a1" : "#89b4fa";
        const text = plugged ? "Plugged In (" + level + "%)" : "On Battery (" + level + "%)";
        show(ic, col, "Power Source", text, Math.min(1.0, level / 100), col);
    }

    Timer {
        id: hideTimer
        interval: 1400
        onTriggered: root.visible = false
    }
}
