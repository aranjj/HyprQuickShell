pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as Services

Singleton {
    id: root

    // ── Dynamic User Paths ─────────────────────────────
    readonly property string homeDir: Quickshell.env("HOME") || ("/home/" + (Quickshell.env("USER") || "user"))

    // ── Persistent Wallpaper Directory Configuration ───
    FileView {
        id: dirFile
        path: root.homeDir + "/.config/quickshell/wallpaper_dir.txt"
        preload: true
        blockLoading: true
    }

    readonly property string savedDir: {
        try {
            let t = dirFile.text().trim();
            if (t.length > 0) {
                if (t.startsWith("/home/")) {
                    const slashIdx = t.indexOf("/", 6);
                    if (slashIdx !== -1) {
                        const userInPath = t.substring(6, slashIdx);
                        const currentUser = Quickshell.env("USER");
                        if (currentUser && userInPath !== currentUser) {
                            t = root.homeDir + t.substring(slashIdx);
                        }
                    }
                } else if (t.startsWith("~")) {
                    t = root.homeDir + t.substring(1);
                }
                return t;
            }
        } catch (e) {}
        return "";
    }

    readonly property string defaultDir: root.homeDir + "/Pictures/Wallpapers"
    property string wallpapersDir: savedDir !== "" ? savedDir : defaultDir

    FileView {
        id: wallFile
        path: root.homeDir + "/.config/quickshell/wallpaper.txt"
        preload: true
        blockLoading: true
    }

    readonly property string savedWallpaper: {
        try {
            let t = wallFile.text().trim();
            if (t.length > 0) {
                const isUri = t.startsWith("file://");
                let clean = isUri ? t.substring(7) : t;
                if (clean.startsWith("/home/")) {
                    const slashIdx = clean.indexOf("/", 6);
                    if (slashIdx !== -1) {
                        const userInPath = clean.substring(6, slashIdx);
                        const currentUser = Quickshell.env("USER");
                        if (currentUser && userInPath !== currentUser) {
                            clean = root.homeDir + clean.substring(slashIdx);
                            t = isUri ? ("file://" + clean) : clean;
                        }
                    }
                } else if (clean.startsWith("~")) {
                    clean = root.homeDir + clean.substring(1);
                    t = isUri ? ("file://" + clean) : clean;
                }
                return t;
            }
        } catch (e) {}
        return "";
    }

    readonly property string defaultWallpaper: "file://" + root.defaultDir + "/blueeve.jpg"

    property string currentWallpaper: savedWallpaper !== "" ? savedWallpaper : defaultWallpaper
    property string currentWallpaperName: extractName(currentWallpaper)
    property var wallpapers: []
    property bool pickerOpen: false

    onPickerOpenChanged: {
        if (!pickerOpen) {
            Services.OverlayCoordinator.releaseExclusiveSurface("wallpaperPicker");
        }
    }

    function togglePicker() {
        if (pickerOpen) closePicker();
        else openPicker();
    }

    function openPicker() {
        scanWallpapers();
        Services.OverlayCoordinator.requestExclusiveSurface("wallpaperPicker");
        pickerOpen = true;
    }

    function closePicker() {
        pickerOpen = false;
        Services.OverlayCoordinator.releaseExclusiveSurface("wallpaperPicker");
    }

    Component.onCompleted: {
        Services.OverlayCoordinator.registerExclusiveSurface("wallpaperPicker",
            () => { openPicker(); },
            () => { closePicker(); }
        );
        scanWallpapers();
    }

    // ── Directory Management ───────────────────────────
    function setWallpapersDir(path) {
        if (!path || path.trim().length === 0) return;
        let clean = path.trim().replace(/\/+$/, "");
        if (clean.startsWith("~")) {
            clean = root.homeDir + clean.substring(1);
        } else if (clean.startsWith("/home/")) {
            const slashIdx = clean.indexOf("/", 6);
            if (slashIdx !== -1) {
                const userInPath = clean.substring(6, slashIdx);
                const currentUser = Quickshell.env("USER");
                if (currentUser && userInPath !== currentUser) {
                    clean = root.homeDir + clean.substring(slashIdx);
                }
            }
        }
        wallpapersDir = clean;
        saveDirProc.command = ["sh", "-c", "echo '" + clean + "' > '" + root.homeDir + "/.config/quickshell/wallpaper_dir.txt'"];
        saveDirProc.running = true;
        scanWallpapers();
    }

    function resetWallpapersDir() {
        setWallpapersDir(defaultDir);
    }

    function scanWallpapers() {
        listProc.command = [
            "sh", "-c",
            "DIR='" + wallpapersDir + "'\n" +
            "if [ ! -d \"$DIR\" ]; then DIR='" + defaultDir + "'; fi\n" +
            "if [ ! -d \"$DIR\" ]; then DIR='" + root.homeDir + "/Pictures'; fi\n" +
            "if [ -d \"$DIR\" ]; then\n" +
            "    find \"$DIR\" -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) | sort\n" +
            "fi"
        ];
        listProc.running = true;
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
            saveProc.command = ["sh", "-c", "echo '" + formatted + "' > '" + root.homeDir + "/.config/quickshell/wallpaper.txt'"];
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
        function setFolder(p: string) { root.setWallpapersDir(p); }
        function resetFolder() { root.resetWallpapersDir(); }
    }

    // ── Process: Discover Wallpapers ───────────────────
    Process {
        id: listProc
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

    // ── Process: Save Directory State ──────────────────
    Process {
        id: saveDirProc
        command: ["sh", "-c", ""]
    }
}
