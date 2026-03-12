// Magic Hat Desktop Wizard — Step 2: Profile Selection
// Reads profile-meta.json via XHR from the Familiar dashboard API,
// falls back to inline data if dashboard is not yet running.
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Kirigami.Page {
    id: page
    title: ""
    padding: 0
    globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

    background: Rectangle { color: "#14161e" }

    // Inline profile data (fallback — profile-meta.json may not be readable yet)
    readonly property var profileData: [
        { id: "ai_companion",    icon: "🤖", label: "AI Companion",
          tagline: "Familiar AI assistant, daily briefings, local inference",
          alwaysOn: true },
        { id: "privacy_suite",   icon: "🔒", label: "Privacy Suite",
          tagline: "Pi-hole ad blocking, SearXNG search, DNS encryption",
          alwaysOn: true },
        { id: "creative_studio", icon: "🎨", label: "Creative Studio",
          tagline: "Krita, Inkscape, Blender, Kdenlive, Darktable",
          alwaysOn: false },
        { id: "gaming",          icon: "🎮", label: "Gaming",
          tagline: "Steam, gamemode, MangoHud, Proton, 32-bit Mesa",
          alwaysOn: false },
        { id: "dev_workstation", icon: "💻", label: "Dev Workstation",
          tagline: "VSCodium, podman-compose, Rust, Go, Node, Python",
          alwaysOn: false }
    ]

    ColumnLayout {
        anchors { fill: parent; margins: 40 }
        spacing: 0

        // Header
        Text {
            text: "Choose your setup"
            color: "#eaeaea"
            font.pixelSize: 26
            font.weight: Font.SemiBold
        }
        Text {
            Layout.topMargin: 6
            Layout.bottomMargin: 28
            text: "AI Companion and Privacy Suite are always included. Add optional stacks — you can change these later."
            color: "#6b7280"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Profile grid (2 columns)
        GridLayout {
            id: grid
            columns: 2
            columnSpacing: 12
            rowSpacing: 12
            Layout.fillWidth: true

            Repeater {
                model: page.profileData
                delegate: ProfileCard {
                    Layout.fillWidth: true
                    profileId:  modelData.id
                    icon:       modelData.icon
                    label:      modelData.label
                    tagline:    modelData.tagline
                    alwaysOn:   modelData.alwaysOn
                    checked:    modelData.alwaysOn ||
                                applicationWindow().selectedProfiles.indexOf(modelData.id) >= 0
                    onToggled: function(id, on) {
                        var profiles = applicationWindow().selectedProfiles.slice()
                        var idx = profiles.indexOf(id)
                        if (on && idx < 0) profiles.push(id)
                        else if (!on && idx >= 0) profiles.splice(idx, 1)
                        applicationWindow().selectedProfiles = profiles
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Back
            Rectangle {
                width: 100; height: 44; radius: 8
                color: backMouse.containsMouse ? "#252745" : "transparent"
                border.color: "#3e4060"; border.width: 1
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "← Back"; color: "#9ca3af"; font.pixelSize: 13 }
                MouseArea {
                    id: backMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: applicationWindow().pageStack.pop()
                }
            }

            Item { Layout.fillWidth: true }

            // Continue
            Rectangle {
                width: 160; height: 44; radius: 8
                color: nextMouse.containsPress ? "#6c7ce8" :
                       nextMouse.containsMouse ? "#8b9cf8" : "#7c8cf8"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "Continue →"; color: "white"; font.pixelSize: 13; font.weight: Font.SemiBold }
                MouseArea {
                    id: nextMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: applicationWindow().nextPage(aiSetupPage)
                }
            }
        }
    }

    // ── Inline Profile Card component ─────────────────────────────────────────
    component ProfileCard: Rectangle {
        id: card
        height: 72
        radius: 10
        border.width: 1

        property string profileId: ""
        property string icon: ""
        property string label: ""
        property string tagline: ""
        property bool alwaysOn: false
        property bool checked: false
        signal toggled(string id, bool on)

        color:        checked ? "#1a1e3a" : "#1e2030"
        border.color: checked ? "#7c8cf8" : "#2e3050"

        Behavior on color        { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 12

            Text { text: card.icon; font.pixelSize: 26 }

            Column {
                Layout.fillWidth: true
                spacing: 3
                Row {
                    spacing: 6
                    Text {
                        text: card.label
                        color: "#eaeaea"
                        font.pixelSize: 13
                        font.weight: Font.SemiBold
                    }
                    Rectangle {
                        visible: card.alwaysOn
                        width: lockLabel.implicitWidth + 10
                        height: 16; radius: 8
                        color: "#1a3a4a"
                        border.color: "#38bdf8"; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text { id: lockLabel; anchors.centerIn: parent; text: "Always On"; color: "#38bdf8"; font.pixelSize: 8 }
                    }
                }
                Text {
                    text: card.tagline
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            // Checkbox
            Rectangle {
                width: 20; height: 20; radius: 4
                color: card.checked ? "#7c8cf8" : "transparent"
                border.color: card.checked ? "#7c8cf8" : "#4b5563"
                border.width: 1.5
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    visible: card.checked
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: card.alwaysOn ? Qt.ArrowCursor : Qt.PointingHandCursor
            enabled: !card.alwaysOn
            onClicked: {
                card.checked = !card.checked
                card.toggled(card.profileId, card.checked)
            }
        }
    }
}
