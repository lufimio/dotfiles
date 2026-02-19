import QtQuick

Item {
    id: root

    enum BarStatus { Hidden = 0, Visible = 1, Expanded = 2 }

    property var config: Config
    property var barStatus: BarStatus
    property alias colors: colorsService

    Colors {
        id: colorsService
    }
}
