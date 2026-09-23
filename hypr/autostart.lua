--------------------------------------------------------------------------------
-- AUTOSTART PROCESSES
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
--------------------------------------------------------------------------------

hl.on("hyprland.start", function()
    -- Quickshell Desktop Environment Shell
    hl.exec_cmd("quickshell -p /home/aran/.config/quickshell/shell.qml")

    -- Clipboard Persist & Watchers
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("wl-paste --type text --watch /home/aran/.config/quickshell/scripts/clipboard-watcher.sh text")
    hl.exec_cmd("wl-paste --type image --watch /home/aran/.config/quickshell/scripts/clipboard-watcher.sh image")

    -- XDG Desktop Portal
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland")
end)
