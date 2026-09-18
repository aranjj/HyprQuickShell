pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string wallpapersDir: "/home/aran/Pictures/Wallpapers"

    FileView {
        id: wallFile
        path: "/home/aran/.config/quickshell/wallpaper.txt"
        preload: true
        blockLoading: true
    }

    readonly property string savedWallpaper: {
        try {
            const t = wallFile.text().trim();
            if (t.length > 0) return t;
        } catch (e) {}
        return "";
    }

    readonly property string defaultWallpaper: "file:///home/aran/Pictures/Wallpapers/blueeve.jpg"

    property string currentWallpaper: savedWallpaper !== "" ? savedWallpaper : defaultWallpaper
    property string currentWallpaperName: extractName(currentWallpaper)
    property var wallpapers: []
    property bool pickerOpen: false

    function togglePicker() {
        pickerOpen = !pickerOpen;
    }

    function openPicker() {
        pickerOpen = true;
    }

    function closePicker() {
        pickerOpen = false;
    }

    // ── Update helper ──────────────────────────────────
    function extractName(path) {
        if (!path) return "Wallpaper";
        const clean = path.replace(/^file:\/\//, "");
        const parts = clean.split("/");
        const filename = parts[parts.length - 1] || "";
        return filename.replace(/\.[^/.]+$/, "").replace(/[-_]/g, " ");
    }

    function setWallpaper(path, persist) {
        if (persist === undefined) persist = true;
        if (!path || path.length === 0) return;
        const formatted = path.startsWith("file://") ? path : ("file://" + path);
        currentWallpaper = formatted;
        currentWallpaperName = extractName(path);

        if (persist) {
            saveProc.command = ["sh", "-c", "echo '" + formatted + "' > /home/aran/.config/quickshell/wallpaper.txt"];
            saveProc.running = true;
        }

        // Generate dynamic Matugen color scheme for the new wallpaper
        ThemeService.generateFromWallpaper(path);
    }

    function nextWallpaper() {
        if (!wallpapers || wallpapers.length === 0) return;
        const currClean = currentWallpaper.replace(/^file:\/\//, "");
        let idx = wallpapers.indexOf(currClean);
        if (idx === -1) idx = 0;
        else idx = (idx + 1) % wallpapers.length;
        setWallpaper(wallpapers[idx]);
    }

    function prevWallpaper() {
        if (!wallpapers || wallpapers.length === 0) return;
        const currClean = currentWallpaper.replace(/^file:\/\//, "");
        let idx = wallpapers.indexOf(currClean);
        if (idx === -1) idx = 0;
        else idx = (idx - 1 + wallpapers.length) % wallpapers.length;
        setWallpaper(wallpapers[idx]);
    }

    function randomWallpaper() {
        if (!wallpapers || wallpapers.length === 0) return;
        const randIdx = Math.floor(Math.random() * wallpapers.length);
        setWallpaper(wallpapers[randIdx]);
    }

    // ── CLI / Keybinding IPC Interface ─────────────────
    IpcHandler {
        target: "wallpaper"
        function next() { root.nextWallpaper(); }
        function prev() { root.prevWallpaper(); }
        function random() { root.randomWallpaper(); }
        function picker() { root.togglePicker(); }
        function togglePicker() { root.togglePicker(); }
        function openPicker() { root.openPicker(); }
        function closePicker() { root.closePicker(); }
    }

    // ── Process: Discover Wallpapers ───────────────────
    Process {
        id: listProc
        command: ["sh", "-c", "find /home/aran/Pictures/Wallpapers -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) | sort"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const list = [];
                for (let i = 0; i < lines.length; i++) {
                    const l = lines[i].trim();
                    if (l.length > 0) list.push(l);
                }
                root.wallpapers = list;
            }
        }
    }

    // ── Process: Save Wallpaper State ──────────────────
    Process {
        id: saveProc
        command: ["sh", "-c", ""]
    }
}
