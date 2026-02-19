import QtQuick
import QtQuick.Layouts
import qs.Core

Rectangle {
    required property Colors colors
    required property string fontFamily
    property var compositor: null
    required property int fontSize

    Layout.preferredHeight: 26
    Layout.preferredWidth: compositor.numWorkspaces * 26 + (compositor.numWorkspaces - 1) * 4 + 4

}
