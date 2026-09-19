pragma Singleton

import Quickshell
import QtQuick
import "." as Services

Singleton {
    id: root

    property bool calendarOpen: false
    onCalendarOpenChanged: {
        if (!calendarOpen) {
            Services.OverlayCoordinator.releaseExclusiveSurface("calendar");
        }
    }

    function toggleCalendar() {
        calendarOpen = !calendarOpen;
        if (calendarOpen) {
            Services.OverlayCoordinator.requestExclusiveSurface("calendar");
        } else {
            Services.OverlayCoordinator.releaseExclusiveSurface("calendar");
        }
    }

    Component.onCompleted: {
        Services.OverlayCoordinator.registerExclusiveSurface("calendar",
            () => {
                calendarOpen = true;
                Services.OverlayCoordinator.requestExclusiveSurface("calendar");
            },
            () => { calendarOpen = false; }
        );
    }

    readonly property string time: Qt.formatDateTime(clock.date, "hh:mm")
    readonly property string date: Qt.formatDateTime(clock.date, "ddd MMM d")
    readonly property string fullDate: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")
    readonly property string macClock: Qt.formatDateTime(clock.date, "ddd MMM d  h:mm AP")
    readonly property date currentDate: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
