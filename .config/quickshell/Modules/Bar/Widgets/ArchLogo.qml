import QtQuick
import QtQuick.Layouts

Rectangle {
    property color bg: "transparent"

    Layout.preferredWidth: 26
    Layout.preferredHeight: 26
    radius: height / 2
    color: bg

    Image {
        anchors.centerIn: parent
        width: 18
        height: 18
        source: "../../../Assets/arch.svg"
        fillMode: Image.PreserveAspectFit
        opacity: 0.9
    }

}
