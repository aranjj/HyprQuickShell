pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    property bool calendarOpen: false

    function toggleCalendar() {
        calendarOpen = !calendarOpen;
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
