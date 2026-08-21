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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 58
            color: "transparent"
            exclusiveZone: 35

            // Network
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

            // Volume
            Process {
                id: volProc
                command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
                running: true
                property real volume: 0
                property bool muted: false

                stdout: StdioCollector {
                    onStreamFinished: {
                        const txt = this.text.trim()
                        const match = txt.match(/Volume:\s+([\d.]+)/)
                        if (match) volProc.volume = parseFloat(match[1])
                        volProc.muted = txt.includes("[MUTED]")
                    }
                }
            }

            Timer {
                interval: 400
                running: true
                repeat: true
                onTriggered: {
                    netProc.running = true
                    volProc.running = true
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
                        font.family: "JetBrainsMono Nerd Font Propo"
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

                    // keep some breathing room between clock and play indicator
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

                        // LOWER minimum so short titles actually shrink
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
                        font.family: "JetBrainsMono Nerd Font Propo"
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

                    // dynamic, but TIGHT for short titles
                    Item {
                        id: mediaGap
                        visible: island.mediaActive
                        Layout.alignment: Qt.AlignVCenter

                        readonly property int gapWidth: {
                            const w = mediaText.dynamicMediaWidth
                            // short titles => 1-2px, long titles => up to 8px
                            return Math.max(1, Math.min(8, Math.round((w - mediaText.minMediaWidth) * 0.02) + 1))
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
                        height: 22

                        property var sortedWorkspaces: {
                            let list = []
                            for (let i = 0; i < Hyprland.workspaces.values.length; i++) list.push(Hyprland.workspaces.values[i])
                            list.sort((a, b) => a.id - b.id)
                            return list
                        }

                        property var workspaceMap: {
                            let map = {}
                            for (let i = 0; i < sortedWorkspaces.length; i++) map[sortedWorkspaces[i].id] = true
                            return map
                        }

                        property int minVisible: 5
                        property int maxWorkspaceId: {
                            let maxId = 0
                            for (let i = 0; i < sortedWorkspaces.length; i++) {
                                if (sortedWorkspaces[i].id > maxId) maxId = sortedWorkspaces[i].id
                            }
                            return maxId
                        }

                        property int slotCount: Math.max(minVisible, maxWorkspaceId)
                        property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                        property int activeIndex: Math.max(0, Math.min(slotCount - 1, activeWorkspaceId - 1))

                        width: slotCount * 22 + Math.max(0, slotCount - 1) * 8

                        Rectangle {
                            id: slime
                            width: 22
                            height: 22
                            radius: 11
                            color: primary
                            y: 0
                            x: wsContainer.activeIndex * (22 + 8)

                            Behavior on x {
                                NumberAnimation {
                                    duration: 420
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        Row {
                            spacing: 8
                            Repeater {
                                model: wsContainer.slotCount
                                Item {
                                    width: 22
                                    height: 22

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
                                        font.family: "JetBrainsMono Nerd Font Propo"
                                    }
                                    MouseArea {
                                      anchors.fill: parent
                                      cursorShape: Qt.PointingHandCursor

                                      onPressed: {
                                        let target = null
                                        for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                                          const w = Hyprland.workspaces.values[i]
                                          if (w.id === parent.wsId) {
                                            target = w
                                            break
                                          }
                                      }

                                    if (target) target.activate()
                                      else Hyprland.dispatch("workspace " + parent.wsId)
                                      }
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
                            text: {
                                if (volProc.muted || volProc.volume === 0) return "󰖁"
                                if (volProc.volume < 0.33) return ""
                                if (volProc.volume < 0.66) return ""
                                return ""
                            }
                            color: volProc.muted ? outline : primary
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 16
                        }

                        Text {
                            text: {
                                if (netProc.status === "wifi") return ""
                                if (netProc.status === "ethernet") return "󰈀"
                                return "󰖪"
                            }
                            color: netProc.status === "disconnected" ? outline : primary
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 16
                        }

                        Text {
                            visible: UPower.displayDevice !== null
                            property var bat: UPower.displayDevice
                            property int pct: bat ? Math.round(bat.percentage * 100) : 0
                            property bool charging: bat && (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged)

                            text: {
                                if (!bat) return ""
                                if (charging) return "󰂄"
                                if (pct < 15) return ""
                                if (pct < 35) return ""
                                if (pct < 55) return ""
                                if (pct < 80) return ""
                                return ""
                            }

                            color: {
                                if (!bat) return "#ffffff"
                                if (charging) return green
                                if (pct <= 15) return red
                                if (pct <= 30) return yellow
                                return "#ffffff"
                            }

                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 16
                        }
                    }
                }
            }
        }
    }
}
