pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property alias server: notifServer
    property bool dnd: false
    property var popups: []
    property var islandNotification: null
    readonly property int unreadCount: notifServer.trackedNotifications && notifServer.trackedNotifications.values ? notifServer.trackedNotifications.values.length : 0

    property var timestamps: {
        try {
            const txt = tsFileView.text();
            if (txt && txt.trim().length > 0) {
                const parsed = JSON.parse(txt.trim());
                if (parsed && typeof parsed === "object") return parsed;
            }
        } catch (e) {}
        return ({});
    }
    readonly property string tsFile: "/home/aran/.cache/quickshell/notification_timestamps.json"

    FileView {
        id: tsFileView
        path: root.tsFile
        preload: true
        blockLoading: true
    }

    Process {
        id: saveTsProc
        running: false
    }

    property bool savePending: false

    function saveTimestamps() {
        if (saveTsProc.running) {
            savePending = true;
            return;
        }
        try {
            const json = JSON.stringify(root.timestamps);
            saveTsProc.command = ["sh", "-c", "mkdir -p ~/.cache/quickshell && printf '%s' '" + json.replace(/'/g, "'\\''") + "' > '" + root.tsFile + "'"];
            saveTsProc.running = true;
        } catch (e) {}
    }

    Connections {
        target: saveTsProc
        function onRunningChanged() {
            if (!saveTsProc.running && root.savePending) {
                root.savePending = false;
                root.saveTimestamps();
            }
        }
    }

    function recordTimestamp(id, timeMs) {
        if (!id && id !== 0) return;
        const key = String(id);
        if (root.timestamps[key]) return;
        const now = timeMs || Date.now();
        let ts = Object.assign({}, root.timestamps);
        ts[key] = now;
        root.timestamps = ts;
        saveTimestamps();
    }

    function getNotificationTime(id) {
        if (!id && id !== 0) return "";
        const key = String(id);
        let t = root.timestamps[key];
        if (!t) {
            recordTimestamp(key, Date.now());
            t = Date.now();
        }
        const notifDate = new Date(Number(t));
        const now = new Date();
        const isToday = notifDate.getDate() === now.getDate() &&
                        notifDate.getMonth() === now.getMonth() &&
                        notifDate.getFullYear() === now.getFullYear();
        if (isToday) {
            return Qt.formatTime(notifDate, "h:mm AP");
        } else {
            return Qt.formatDateTime(notifDate, "MMM d, h:mm AP");
        }
    }

    function getRelativeTime(id, tick) {
        return getNotificationTime(id);
    }

    Timer {
        id: islandTimer
        interval: 3000
        onTriggered: root.islandNotification = null
    }

    function dismissIsland() {
        islandNotification = null;
        islandTimer.stop();
    }

    // Sound process
    Process {
        id: soundProc
        command: ["sh", "-c", "canberra-gtk-play -i message 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null"]
    }

    function playSound() {
        if (root.dnd) return;
        soundProc.running = true;
    }

    function toggleDnd() {
        dnd = !dnd;
    }

    function clearAll() {
        if (!notifServer.trackedNotifications) return;
        const list = [...notifServer.trackedNotifications.values];
        for (let i = 0; i < list.length; i++) {
            try {
                list[i].dismiss();
            } catch (e) {}
        }
        popups = [];
        timestamps = ({});
        saveTimestamps();
        dismissIsland();
    }

    function dismiss(notif) {
        if (!notif) return;
        removePopup(notif.id);
        try {
            notif.dismiss();
        } catch (e) {}
    }

    function removePopup(id) {
        popups = popups.filter(p => p.id !== id);
        if (root.islandNotification && root.islandNotification.id === id) {
            root.dismissIsland();
        }
    }

    function addPopup(notif) {
        console.log("[NotificationService] addPopup called, dnd:", root.dnd, "summary:", notif.summary);
        if (root.dnd) return;
        playSound();

        // Remove any existing popup with the same ID
        let current = popups.filter(p => p.id !== notif.id);

        const item = {
            id: notif.id,
            notif: notif,
            appName: notif.appName && notif.appName.length > 0 ? notif.appName : "Notification",
            appIcon: notif.appIcon || "",
            summary: notif.summary || "",
            body: notif.body || "",
            image: notif.image || "",
            timeStr: Qt.formatTime(new Date(), "h:mm AP")
        };

        current.unshift(item);
        // Keep at most 4 active floating banners
        if (current.length > 4) {
            current.pop();
        }
        root.popups = current;
        root.islandNotification = item;
        islandTimer.restart();
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        persistenceSupported: true

        onNotification: (notif) => {
            notif.tracked = true;
            root.recordTimestamp(notif.id, Date.now());
            root.addPopup(notif);

            notif.closed.connect(() => {
                root.removePopup(notif.id);
                let ts2 = Object.assign({}, root.timestamps);
                delete ts2[notif.id];
                root.timestamps = ts2;
                root.saveTimestamps();
            });
        }
    }
}
