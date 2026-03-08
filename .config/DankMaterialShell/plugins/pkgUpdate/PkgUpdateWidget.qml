import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property var pacmanUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []
    property bool pacmanChecking: true
    property bool aurChecking: true
    property bool flatpakChecking: true

    // ── Settings (from plugin data) ───────────────────────────────────────────
    property string terminalApp: pluginData.terminalApp || "kitty"
    property int refreshMins: pluginData.refreshMins || 60

    property bool checkingUpdates: pacmanChecking || aurChecking || flatpakChecking
    property int totalUpdates: pacmanUpdates.length + aurUpdates.length + flatpakUpdates.length

    popoutWidth: 480

    // ── Periodic refresh ──────────────────────────────────────────────────────
    Timer {
        interval: root.refreshMins * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkUpdates()
    }

    // ── Update check functions ────────────────────────────────────────────────
    function checkUpdates() {
        root.pacmanChecking = true;
        Proc.runCommand("pkgUpdate.pacman", ["sh", "-c", "checkupdates 2> /dev/null"], (stdout, exitCode) => {
            root.pacmanUpdates = parsePacmanPackages(stdout);
            root.pacmanChecking = false;
        }, 100)

        root.aurChecking = true;
        Proc.runCommand("pkgUpdate.aur", ["sh", "-c", "yay -Qu 2> /dev/null"], (stdout, exitCode) => {
            root.aurUpdates = parsePacmanPackages(stdout);
            root.aurChecking = false;
        }, 100)

        root.flatpakChecking = true;
        Proc.runCommand("pkgUpdate.flatpak", ["sh", "-c", "flatpak remote-ls --updates --user --system 2> /dev/null"], (stdout, exitCode) => {
            root.flatpakUpdates = parseFlatpakApps(stdout);
            root.flatpakChecking = false;
        }, 100)
    }

    function parsePacmanPackages(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return [];
        return stdout.trim().split('\n').filter(line => line.trim().length > 0).map(line => {
            const parts = line.trim().split(/\s+/);
            return {
                name: parts[0] || '',
                local: parts[1] || '',
                remote: parts[3] || ''
            };
        }).filter(a => a.name.length > 0);
    }

    function parseFlatpakApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return [];
        return stdout.trim().split('\n').filter(line => line.trim().length > 0).map(line => {
            const parts = line.trim().split(/\t|\s{2,}/);
            return {
                name: parts[0] || '',
                branch: parts[1] || '',
                origin: parts[2] || ''
            };
        }).filter(a => a.name.length > 0);
    }

    // ── Terminal launch ───────────────────────────────────────────────────────
    function runAllUpdates() {
        root.closePopout();
        const cmd = "flatpak update -y; yay --noconfirm; echo; echo '=== Done. Press Enter to close. ==='; read";
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"]);
    }

    function runPacmanUpdate() {
        root.closePopout();
        const cmd = "sudo pacman -Syu --noconfirm; echo; echo '=== Done. Press Enter to close. ==='; read";
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"]);
    }

    function runAurUpdate() {
        root.closePopout();
        const cmd = "yay -Syua --noconfirm; echo; echo '=== Done. Press Enter to close. ==='; read";
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"]);
    }

    function runFlatpakUpdate() {
        root.closePopout();
        const cmd = "flatpak update -y; echo; echo '=== Done. Press Enter to close. ==='; read";
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"]);
    }

    // ── Bar pills ─────────────────────────────────────────────────────────────
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.checkingUpdates ? "…" : (root.totalUpdates > 0 ? root.totalUpdates.toString() : '')
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.pacmanChecking || root.aurChecking || root.flatpakChecking) ? "…" : (root.totalUpdates > 0 ? root.totalUpdates.toString() : '')
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ── Popout ────────────────────────────────────────────────────────────────
    popoutContent: Component {
        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Header card
            Item {
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }

                        DankIcon {
                            name: "system_update"
                            size: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                        }


                        MouseArea {
                            id: updateBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAllUpdates()
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            text: "Package Updates"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.totalUpdates > 0 ? root.totalUpdates + " update" + (root.totalUpdates !== 1 ? "s" : "") + " available" : "System is up to date"
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                        }
                    }
                }


                // Refresh button
                Item {
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    DankIcon {
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.checkUpdates()
                    }
                }
            }

            // ── Pacman section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "archive"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Pacman"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: pacmanCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: pacmanCountLabel
                            text: root.pacmanChecking ? "…" : root.pacmanUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Pacman button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: pacmanBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.pacmanChecking && root.pacmanUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: pacmanBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: pacmanBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: pacmanBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Pacman"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: pacmanBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: pacmanBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runPacmanUpdate()
                    }
                }
            }

            // ── Pacman update list ──────────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.pacmanChecking ? 52 : (root.pacmanUpdates.length === 0 ? 46 : Math.min(root.pacmanUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.pacmanChecking

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.pacmanChecking && root.pacmanUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.pacmanUpdates
                    spacing: 2
                    visible: !root.pacmanChecking && root.pacmanUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string pkgName: modelData.name
                        property string pkgLocal: modelData.local
                        property string pkgRemote: modelData.remote

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "upgrade"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pkgName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - pkgVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: pkgVersionText
                                text: pkgLocal + " -> " + pkgRemote
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── AUR section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "archive"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "AUR"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: aurCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: aurCountLabel
                            text: root.aurChecking ? "…" : root.aurUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update AUR button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: aurBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.aurChecking && root.aurUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: aurBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: aurBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: aurBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update AUR"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: aurBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: aurBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAurUpdate()
                    }
                }
            }

            // ── AUR update list ──────────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.aurChecking ? 52 : (root.aurUpdates.length === 0 ? 46 : Math.min(root.aurUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.aurChecking

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.aurChecking && root.aurUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.aurUpdates
                    spacing: 2
                    visible: !root.aurChecking && root.aurUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string pkgName: modelData.name
                        property string pkgLocal: modelData.local
                        property string pkgRemote: modelData.remote

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "upgrade"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pkgName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - pkgVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: pkgVersionText
                                text: pkgLocal + " -> " + pkgRemote
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── Flatpak section header ────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "apps"
                        size: 20
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Flatpak"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: flatpakCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: flatpakCountLabel
                            text: root.flatpakChecking ? "…" : root.flatpakUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.secondary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Flatpak button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: flatpakBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.flatpakChecking && root.flatpakUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: flatpakBtnArea.containsMouse ? Theme.secondary : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: flatpakBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Flatpak"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: flatpakBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runFlatpakUpdate()
                    }
                }
            }

            // ── Flatpak update list ──────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.flatpakChecking ? 52 : (root.flatpakUpdates.length === 0 ? 46 : Math.min(root.flatpakUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.flatpakChecking

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.flatpakChecking && root.flatpakUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.flatpakUpdates
                    spacing: 2
                    visible: !root.flatpakChecking && root.flatpakUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string appId: modelData.name
                        property string appOrigin: modelData.origin

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "extension"
                                size: 14
                                color: Theme.secondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: appId
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - appOriginText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: appOriginText
                                text: appOrigin
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
