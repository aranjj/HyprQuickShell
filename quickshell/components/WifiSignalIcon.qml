import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real signal: 100
    property color color: "#ffffff"
    property real size: 14

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size

    readonly property int bars: {
        const s = signal || 0;
        if (s >= 70) return 3;
        if (s >= 35) return 2;
        if (s > 0) return 1;
        return 0;
    }

    // Top Arc (3rd bar)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false
        opacity: root.bars >= 3 ? 1.0 : 0.22
        Behavior on opacity { NumberAnimation { duration: 150 } }

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0
            scale: Qt.size(root.width / 24, root.height / 24)
            PathSvg {
                path: "M3.71 8.84Q3.41 9.13 2.995 9.115Q2.58 9.1 2.3 8.81Q2.01 8.51 2.02 8.095Q2.03 7.68 2.32 7.4Q4.23 5.55 6.735 4.53Q9.24 3.51 12.01 3.51Q14.78 3.5 17.275 4.53Q19.77 5.56 21.69 7.41Q21.98 7.69 21.99 8.095Q22.0 8.5 21.71 8.81Q21.43 9.1 21.015 9.115Q20.6 9.13 20.3 8.84Q18.65 7.26 16.515 6.38Q14.38 5.5 12.01 5.5Q9.64 5.5 7.495 6.38Q5.35 7.26 3.71 8.84Z"
            }
        }
    }

    // Middle Arc (2nd bar)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false
        opacity: root.bars >= 2 ? 1.0 : 0.22
        Behavior on opacity { NumberAnimation { duration: 150 } }

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0
            scale: Qt.size(root.width / 24, root.height / 24)
            PathSvg {
                path: "M7.38 12.25Q7.07 12.52 6.655 12.495Q6.24 12.47 5.97 12.155Q5.7 11.84 5.72 11.425Q5.74 11.01 6.06 10.74Q7.27 9.69 8.8 9.095Q10.33 8.5 12.01 8.5Q13.69 8.5 15.21 9.095Q16.73 9.69 17.95 10.74Q18.26 11.01 18.285 11.425Q18.31 11.84 18.04 12.155Q17.77 12.47 17.36 12.495Q16.95 12.52 16.63 12.25Q15.69 11.41 14.505 10.955Q13.32 10.5 12.01 10.5Q10.7 10.5 9.515 10.955Q8.33 11.41 7.38 12.25Z"
            }
        }
    }

    // Dot (1st bar)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false
        opacity: root.bars >= 1 ? 1.0 : 0.22
        Behavior on opacity { NumberAnimation { duration: 150 } }

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0
            scale: Qt.size(root.width / 24, root.height / 24)
            PathSvg {
                path: "M12.01 17.49Q11.18 17.5 10.59 16.905Q10.0 16.31 10.01 15.49Q10.0 14.67 10.59 14.08Q11.18 13.49 12.01 13.49Q12.82 13.49 13.41 14.08Q14.0 14.67 14.0 15.49Q14.0 16.31 13.42 16.905Q12.84 17.5 12.01 17.49Z"
            }
        }
    }
}
