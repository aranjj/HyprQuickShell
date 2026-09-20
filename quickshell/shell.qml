//@ pragma UseQApplication
//@ pragma Env QSG_RENDER_LOOP=threaded

import Quickshell
import QtQuick
import "bar"
import "components"

ShellRoot {
    Wallpaper {}
    WallpaperPicker {}
    Bar {}
    DynamicIsland {}
    ControlCenter {}
    PowerMenu {}
    OSD {}
    AppLauncher {}
    CalendarView {}
    Clipboard {}
    EmojiPicker {}
    LockScreen {}
    // NotificationToast {} - Handled directly by Dynamic Island morphing!
    AboutDialog {}
    ScreenshotToolbar {}
    ScreenshotPreview {}
    PolkitDialog {}
}
