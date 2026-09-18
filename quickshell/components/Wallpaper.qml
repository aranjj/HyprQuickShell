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
            "parallaxRight",
            "parallaxLeft",
            "parallaxUp",
            "parallaxDown",
            "parallaxZoomIn",
            "parallaxZoomOut"
        ]

        function triggerTransition(newWall) {
            if (transitionAnim.running) {
                transitionAnim.stop();
                activeImgSource = targetImgSource;
            }

            // Select random fade / parallax transition
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

            // Parallax drift coordinates
            x: {
                if (bgWindow.currentTransition === "parallaxRight") return -bgWindow.animProgress * 40;
                if (bgWindow.currentTransition === "parallaxLeft") return bgWindow.animProgress * 40;
                return 0;
            }

            y: {
                if (bgWindow.currentTransition === "parallaxUp") return -bgWindow.animProgress * 30;
                if (bgWindow.currentTransition === "parallaxDown") return bgWindow.animProgress * 30;
                return 0;
            }

            scale: {
                if (bgWindow.currentTransition === "parallaxZoomIn") return 1.0 - 0.05 * bgWindow.animProgress;
                if (bgWindow.currentTransition === "parallaxZoomOut") return 1.0 + 0.04 * bgWindow.animProgress;
                return 1.0;
            }

            opacity: 1.0 - bgWindow.animProgress

            Image {
                id: currentImg
                anchors.fill: parent
                // Bleed margins prevent black edges during parallax drift
                anchors.margins: -60
                fillMode: Image.PreserveAspectCrop
                source: bgWindow.activeImgSource
                asynchronous: false
                cache: true
                smooth: true
            }
        }

        // ── Next Wallpaper Layer (Parallax In + Crossfade) ─
        Item {
            id: nextLayer
            anchors.fill: parent
            clip: true
            visible: bgWindow.targetImgSource !== ""

            // Parallax slide-in coordinates
            x: {
                if (bgWindow.currentTransition === "parallaxRight") return (1.0 - bgWindow.animProgress) * 55;
                if (bgWindow.currentTransition === "parallaxLeft") return -(1.0 - bgWindow.animProgress) * 55;
                return 0;
            }

            y: {
                if (bgWindow.currentTransition === "parallaxUp") return (1.0 - bgWindow.animProgress) * 45;
                if (bgWindow.currentTransition === "parallaxDown") return -(1.0 - bgWindow.animProgress) * 45;
                return 0;
            }

            scale: {
                if (bgWindow.currentTransition === "parallaxZoomIn") return 1.06 - 0.06 * bgWindow.animProgress;
                if (bgWindow.currentTransition === "parallaxZoomOut") return 0.94 + 0.06 * bgWindow.animProgress;
                if (bgWindow.currentTransition === "fade") return 1.015 - 0.015 * bgWindow.animProgress;
                return 1.0;
            }

            opacity: bgWindow.animProgress

            Image {
                id: nextImg
                anchors.fill: parent
                anchors.margins: -60
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
