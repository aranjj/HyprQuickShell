import Quickshell
import Quickshell.Wayland
import QtQuick
import "../services" as Services

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bgWindow
        required property ShellScreen modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell-wallpaper"
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "#050508"

        // ── Transition State ─────────────────────────────
        property string activeImgSource: ""
        property string targetImgSource: ""
        property string currentTransition: "fade"
        property real animProgress: 0.0

        Component.onCompleted: {
            activeImgSource = Services.WallpaperService.currentWallpaper;
        }

        readonly property var transitionPool: [
            "fade",
            "crossfade",
            "zoomIn",
            "zoomOut"
        ]

        function triggerTransition(newWall) {
            if (transitionAnim.running) {
                transitionAnim.stop();
                activeImgSource = targetImgSource;
            }

            // Select transition
            const rand = transitionPool[Math.floor(Math.random() * transitionPool.length)];
            currentTransition = rand;
            animProgress = 0.0;
            targetImgSource = newWall;

            console.log("[Wallpaper] Transitioning with:", rand, "to:", newWall);

            if (nextImg.status === Image.Ready) {
                transitionAnim.restart();
            }
        }

        NumberAnimation {
            id: transitionAnim
            target: bgWindow
            property: "animProgress"
            from: 0.0
            to: 1.0
            duration: 800
            easing.type: Easing.InOutCubic

            onFinished: {
                bgWindow.activeImgSource = bgWindow.targetImgSource;
                Qt.callLater(() => {
                    bgWindow.targetImgSource = "";
                    bgWindow.animProgress = 0.0;
                });
            }
        }

        // ── Current Wallpaper Layer ──────────────────────
        Item {
            id: currentLayer
            anchors.fill: parent
            clip: true

            scale: {
                if (bgWindow.currentTransition === "zoomOut") return 1.0 - 0.03 * bgWindow.animProgress;
                return 1.0;
            }

            opacity: 1.0 - bgWindow.animProgress

            Image {
                id: currentImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: bgWindow.activeImgSource
                asynchronous: false
                cache: true
                smooth: true
            }
        }

        // ── Next Wallpaper Layer (Crossfade + In) ─────────
        Item {
            id: nextLayer
            anchors.fill: parent
            clip: true
            visible: bgWindow.targetImgSource !== ""

            scale: {
                if (bgWindow.currentTransition === "zoomIn") return 1.03 - 0.03 * bgWindow.animProgress;
                if (bgWindow.currentTransition === "zoomOut") return 0.97 + 0.03 * bgWindow.animProgress;
                return 1.0;
            }

            opacity: bgWindow.animProgress

            Image {
                id: nextImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: bgWindow.targetImgSource
                asynchronous: true
                cache: true
                smooth: true

                onStatusChanged: {
                    if (status === Image.Ready && bgWindow.targetImgSource !== "" && !transitionAnim.running) {
                        transitionAnim.restart();
                    }
                }
            }
        }

        Connections {
            target: Services.WallpaperService
            function onCurrentWallpaperChanged() {
                const newWall = Services.WallpaperService.currentWallpaper;
                if (!newWall || newWall === bgWindow.activeImgSource) return;

                if (bgWindow.activeImgSource === "") {
                    bgWindow.activeImgSource = newWall;
                } else {
                    bgWindow.triggerTransition(newWall);
                }
            }
        }
    }
}
