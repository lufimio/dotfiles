import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string targetAddress: ""
    readonly property var source: Hyprland.toplevels.values.find(
        t => t.address.toLowerCase().replace(/^0x/, "") === targetAddress.toLowerCase().replace(/^0x/, "")
    ) ?? null
    // Never mirror ourselves or any other window placed in the capture workspace.
    readonly property bool allowed: targetAddress !== "" && source !== null
        && source.workspace?.name !== "dynamic-cast"
        && !(source.lastIpcObject?.tags ?? []).some(t => t.replace(/\*$/, "") === "capture-private")

    Socket {
        id: control
        path: Quickshell.env("HYPR_DYNAMIC_CAST_SOCKET")
        connected: true
        onConnectionStateChanged: {
            if (connected) {
                write('{"op":"view"}\n')
                flush()
            } else {
                root.targetAddress = ""
                Qt.quit()
            }
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    root.targetAddress = JSON.parse(data).address ?? ""
                } catch (error) {
                    root.targetAddress = ""
                }
            }
        }
    }

    FloatingWindow {
        title: "Hyprland Dynamic Cast"
        visible: true
        implicitWidth: 1280
        implicitHeight: 720
        color: "black"
        maximized: true

        ScreencopyView {
            id: capture
            anchors.centerIn: parent
            live: true
            paintCursor: false
            captureSource: root.allowed ? root.source.wayland : null
            // Letterbox, never stretch or crop; stale/blocked content is hidden.
            readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1
            width: Math.min(parent.width, parent.height * aspect)
            height: width / aspect
            visible: root.allowed && hasContent
            onStopped: root.targetAddress = ""
        }
        Text {
            anchors.centerIn: parent
            visible: !capture.visible
            color: "#899298"
            text: "No window shared\nFocus a window and press Super+Shift+R"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
