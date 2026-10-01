import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Io

ShellRoot {
    readonly property color bg:        "#111111"
    readonly property color text:      "#f2f4f8"
    readonly property color primary:   "#ff7eb6"
    readonly property color primaryFg: "#000000"
    readonly property color outline:   "#525252"
    readonly property color green:     "#42be65"
    readonly property color yellow:    "#ffe97b"
    readonly property color red:       "#ee5396"

    readonly property string monoFont: "JetBrainsMono Nerd Font"

    readonly property int batLowPct:  15
    readonly property int batMidPct:  35
    readonly property int batHighPct: 55
    readonly property int batFullPct: 80

    QtObject {
        id: osd
        property bool shown: false
        property bool hiding: false
        property string mode: "volume"

        function trigger(which) {
            mode = which
            hiding = false
            shown = true
            hideTimer.restart()
        }
    }

  Timer {
        id: hideTimer
        interval: 1500
        onTriggered: {
            osd.hiding = true
            unmapTimer.restart()
        }
    }

    Timer {
        id: unmapTimer
        interval: 200
        onTriggered: osd.shown = false
    }

    Variants {
        model: Quickshell.screens

        Item {
            id: screenRoot
            required property var modelData

        PanelWindow {
            id: panel
            screen: screenRoot.modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 58
            color: "transparent"
            exclusiveZone: 35

            Process {
                id: netProc
                command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"]
                running: true
                property string status: "disconnected"

                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = this.text.trim().split("\n")
                        let found = "disconnected"
                        for (const line of lines) {
                            const parts = line.split(":")
                            if (parts.length < 3) continue
                            if (parts[2] === "connected") {
                                if (parts[1] === "wifi") { found = "wifi"; break }
                                if (parts[1] === "ethernet") { found = "ethernet"; break }
                            }
                        }
                        netProc.status = found
                    }
                }
            }

            Process {
              id: volProc
              command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
              running: true
              property real volume: 0
              property bool muted: false
              property bool primed: false

              readonly property string currentIcon: {
                if (muted || volume === 0) return "󰖁"
                if (volume < 0.33) return "󰕿"
                if (volume < 0.66) return "󰖀"
                return "󰕾"
              }

                stdout: StdioCollector {
                    onStreamFinished: {
                        const txt = this.text.trim()
                        const match = txt.match(/Volume:\s+([\d.]+)/)
                        const newVolume = match ? parseFloat(match[1]) : volProc.volume
                        const newMuted = txt.includes("[MUTED]")
                        const changed = volProc.primed &&
                            (newVolume !== volProc.volume || newMuted !== volProc.muted)

                        volProc.volume = newVolume
                        volProc.muted = newMuted
                        volProc.primed = true

                        if (changed) osd.trigger("volume")
                    }
                }
            }

            Process {
                id: brightProc
                command: ["brightnessctl", "-m"]
                running: true
                property real percent: 100
                property bool primed: false

                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = this.text.trim().split(",")
                        let newPercent = brightProc.percent
                        for (const part of parts) {
                            if (part.endsWith("%")) {
                                const parsed = parseFloat(part)
                                if (!isNaN(parsed)) newPercent = parsed
                                break
                            }
                        }
                        const changed = brightProc.primed && newPercent !== brightProc.percent

                        brightProc.percent = newPercent
                        brightProc.primed = true

                        if (changed) osd.trigger("brightness")
                    }
                }
            }

            Process {
                id: volWatcher
                command: ["sh", "-c", "pw-mon | grep -m 1 'changed'"]
                running: true
                onRunningChanged: {
                    if (!running) {
                        volProc.running = true
                        running = true
                    }
                }
            }

            Process {
                id: brightWatcher
                command: ["sh", "-c", "udevadm monitor -s backlight | grep -m 1 'change'"]
                running: true
                onRunningChanged: {
                    if (!running) {
                        brightProc.running = true
                        running = true
                    }
                }
            }


            Process {
              id: netWatcher
              command: ["sh", "-c", "ip monitor link | grep -m 1 'state'"]
              running: true
              onRunningChanged: {
                if (!running) {
                  netProc.running = true // Trigger the nmcli fetch
                  running = true         // Immediately restart the watcher
                }
              }
           }


            Rectangle {
                id: island

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                clip: true

                readonly property int sideMargins: 32
                readonly property int rowSpacing: 10

                property bool mediaActive: {
                    for (let i = 0; i < Mpris.players.values.length; i++) {
                        const p = Mpris.players.values[i]
                        if (p.isPlaying || p.playbackState === MprisPlaybackState.Paused)
                            return true
                    }
                    return false
                }

                property real targetWidth: {
                    const clockW = clockText.implicitWidth
                    const clockMediaGapW = mediaActive ? clockMediaGap.gapWidth : 0
                    const mediaW = mediaActive ? mediaText.dynamicMediaWidth : 0
                    const gapW = mediaActive ? mediaGap.gapWidth : 0
                    const wsW = wsContainer.width
                    const iconsW = statusIcons.implicitWidth
                    const blocks = 3 + (mediaActive ? 3 : 0)
                    const spacings = Math.max(0, blocks - 1) * rowSpacing
                    const raw = sideMargins + clockW + clockMediaGapW + mediaW + gapW + wsW + iconsW + spacings
                    return Math.max(320, Math.round(raw))
                }

                property real displayWidth: targetWidth
                width: displayWidth

                Behavior on targetWidth {
                    SmoothedAnimation {
                        velocity: 900
                        duration: 260
                    }
                }

                Behavior on displayWidth {
                    NumberAnimation {
                        duration: 520
                        easing.type: Easing.OutCubic
                    }
                }

                onTargetWidthChanged: displayWidth = targetWidth

                height: 40
                radius: 99
                color: bg
                border.color: "#222222"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: island.rowSpacing

                    Text {
                        id: clockText
                        text: Qt.formatTime(new Date(), "h:mm AP")
                        color: "#ffffff"
                        font.family: monoFont
                        font.pixelSize: 15
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter

                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: parent.text = Qt.formatTime(new Date(), "h:mm AP")
                        }
                    }

                    Item {
                        id: clockMediaGap
                        visible: island.mediaActive
                        Layout.alignment: Qt.AlignVCenter
                        readonly property int gapWidth: 8
                        Layout.preferredWidth: gapWidth
                        Layout.minimumWidth: gapWidth
                        Layout.maximumWidth: gapWidth
                        height: 1
                    }

                    Text {
                        id: mediaText
                        visible: island.mediaActive
                        Layout.alignment: Qt.AlignVCenter

                        readonly property int minMediaWidth: 70
                        readonly property int maxMediaWidth: 420
                        readonly property int dynamicMediaWidth: Math.max(
                            minMediaWidth,
                            Math.min(maxMediaWidth, implicitWidth)
                        )

                        Layout.preferredWidth: dynamicMediaWidth
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: maxMediaWidth

                        elide: Text.ElideRight
                        color: primary
                        font.family: monoFont
                        font.pixelSize: 14
                        font.weight: Font.DemiBold

                        text: {
                            for (let i = 0; i < Mpris.players.values.length; i++) {
                                const p = Mpris.players.values[i]
                                if (p.isPlaying || p.playbackState === MprisPlaybackState.Paused) {
                                    const icon = p.isPlaying ? "󰏤" : "󰐊"
                                    return icon + "  " + (p.trackTitle || "")
                                }
                            }
                            return ""
                        }
                    }

                    Item {
                        id: mediaGap
                        visible: island.mediaActive
                        Layout.alignment: Qt.AlignVCenter

                        readonly property real gapScaleFactor: 0.02
                        readonly property int gapWidth: {
                            const w = mediaText.dynamicMediaWidth
                            return Math.max(1, Math.min(8, Math.round((w - mediaText.minMediaWidth) * gapScaleFactor) + 1))
                        }

                        Layout.preferredWidth: gapWidth
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: 8
                        height: 1
                    }

                    Item {
                        id: wsContainer
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: width
                        Layout.minimumWidth: width
                        Layout.maximumWidth: width
                        height: wsSlotSize

                        readonly property int wsSlotSize: 22
                        readonly property int wsSlotSpacing: 8

                        property var workspaceMap: {
                          let map = {}
                          for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                            map[Hyprland.workspaces.values[i].id] = true
                          }
                          return map
                        }

                        property int maxWorkspaceId: {
                          let maxId = 0
                          for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                            const currentId = Hyprland.workspaces.values[i].id
                            if (currentId > maxId) maxId = currentId
                          }
                        return maxId
                        }

                        property int minVisible: 5

                        property int slotCount: Math.max(minVisible, maxWorkspaceId)
                        property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                        property int activeIndex: Math.max(0, Math.min(slotCount - 1, activeWorkspaceId - 1))

                        width: slotCount * wsSlotSize + Math.max(0, slotCount - 1) * wsSlotSpacing

                        Rectangle {
                            id: slime
                            width: wsContainer.wsSlotSize
                            height: wsContainer.wsSlotSize
                            radius: wsContainer.wsSlotSize / 2
                            color: primary
                            y: 0
                            x: wsContainer.activeIndex * (wsContainer.wsSlotSize + wsContainer.wsSlotSpacing)

                            Behavior on x {
                                NumberAnimation {
                                    duration: 420
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        Row {
                            spacing: wsContainer.wsSlotSpacing
                            Repeater {
                                model: wsContainer.slotCount
                                Item {
                                    width: wsContainer.wsSlotSize
                                    height: wsContainer.wsSlotSize

                                    required property int index
                                    property int wsId: index + 1
                                    property bool exists: !!wsContainer.workspaceMap[wsId]
                                    property bool isActive: wsId === wsContainer.activeWorkspaceId

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.wsId
                                        color: parent.exists ? "#ffffff" : outline
                                        opacity: parent.exists ? 1.0 : 0.55
                                        font.pixelSize: 13
                                        font.bold: parent.isActive
                                        font.family: monoFont
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor

                                        onPressed: Hyprland.dispatch("workspace " + parent.wsId)
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        id: statusIcons
                        spacing: 20
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: implicitWidth
                        Layout.minimumWidth: implicitWidth
                        Layout.maximumWidth: implicitWidth

                        Text {
                          text: volProc.currentIcon
                          color: volProc.muted ? outline : primary
                          font.family: monoFont
                          font.pixelSize: 16
                        }

                        Text {
                            text: {
                                if (netProc.status === "wifi") return "󰖩"
                                if (netProc.status === "ethernet") return "󰈀"
                                return "󰖪"
                            }
                            color: netProc.status === "disconnected" ? outline : primary
                            font.family: monoFont
                            font.pixelSize: 16
                        }

                        Text {
                            visible: UPower.displayDevice !== null
                            property var bat: UPower.displayDevice
                            property int pct: bat ? Math.round(bat.percentage * 100) : 0
                            property bool charging: bat && bat.state !== UPowerDeviceState.Discharging

                            text: {
                                if (!bat) return ""
                                if (charging) return "󰂄"
                                if (pct < batLowPct) return "󰁺"
                                if (pct < batMidPct) return "󰁼"
                                if (pct < batHighPct) return "󰁾"
                                if (pct < batFullPct) return "󰂀"
                                return ""
                            }

                            color: {
                                if (!bat) return "#ffffff"
                                if (charging) return green
                                if (pct <= batLowPct) return red
                                if (pct <= batMidPct) return yellow
                                return "#ffffff"
                            }

                            font.family: monoFont
                            font.pixelSize: 16
                        }
                    }
                }
            }
        }

        PanelWindow {
            id: osdPanel
            screen: screenRoot.modelData

            anchors { bottom: true }
            margins.bottom: 48
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            visible: osd.shown

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-osd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            implicitWidth: osdPill.width
            implicitHeight: osdPill.height

            Rectangle {
                id: osdPill
                width: 220
                height: 52
                radius: 26
                color: bg
                border.color: "#222222"
                border.width: 1

                opacity: osd.hiding ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                readonly property real value: osd.mode === "brightness"
                    ? (brightProc.percent / 100)
                    : (volProc.muted ? 0 : volProc.volume)

                readonly property string icon: {
                  if (osd.mode === "brightness") return "󰃟"
                  return volProc.currentIcon
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 12

                    Text {
                        text: osdPill.icon
                        color: primary
                        font.family: monoFont
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        id: track
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: 3
                        color: outline
                        opacity: 0.4

                        Rectangle {
                            width: track.width * osdPill.value
                            height: parent.height
                            radius: parent.radius
                            color: primary

                            Behavior on width {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Text {
                        text: Math.round(osdPill.value * 100) + "%"
                        color: "#ffffff"
                        font.family: monoFont
                        font.pixelSize: 13
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 34
                    }
                }
            }
        }
    }
    }
}
