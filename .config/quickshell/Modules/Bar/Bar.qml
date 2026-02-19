import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Modules.Bar.Widgets

Rectangle {
    id: barRoot

    required property Colors colors
    required property string fontFamily
    required property int fontSize

    anchors.fill: parent
    color: colors.bg
    radius: 15

    /*
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        spacing: 5

        ArchLogo {
            bg: logoMouseArea.containsMouse ? barRoot.colors.bg_bright : "transparent"
            MouseArea {
                id: logoMouseArea
                anchors.fill: parent
                hoverEnabled: true

                onClicked: (mouse) => {
                    if (mouse.button == Qt.LeftButton) {
                        console.log("Logo Clicked")
                    }
                }
            }
        }

        VerticalDivider {
            colors: barRoot.colors
        }

        Workspaces {
            colors: barRoot.colors
            fontFamily: barRoot.fontFamily
            fontSize: barRoot.fontSize
        }

        Item {
            Layout.fillWidth: true
        }

        ArchLogo {}

        Item {
            Layout.fillWidth: true
        }

        ArchLogo {}
    }
    */
}
