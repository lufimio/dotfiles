import QtQuick
import Quickshell
import qs.Core
import qs.Modules.Bar

Variants {
    id: root
    model: Quickshell.screens

    required property Context context

    PanelWindow {
        property var modelData

        screen: modelData
        implicitHeight: 5

        color: "transparent"

        anchors {
            top: true
            bottom: false
            left: true
            right: true
        }

        margins {
            top: 0
            bottom: 0
            left: 0
            right: 0
        }

        Bar {
            colors: root.context.colors
            fontFamily: root.context.config.fontFamily
            fontSize: root.context.config.fontSize
        }
    }
}
