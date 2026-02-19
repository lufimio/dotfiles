import QtQuick
import QtQuick.Layouts

Rectangle {
    required property var colors

    Layout.preferredWidth: 1
    Layout.preferredHeight: 20
    Layout.alignment: Qt.AlignVCenter
    color: colors.outline
    opacity: 0.5
}
