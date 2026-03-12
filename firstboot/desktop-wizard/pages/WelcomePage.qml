// Magic Hat Desktop Wizard — Step 1: Welcome
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

    // No toolbar chrome
    globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

    background: Rectangle {
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#0d0f1a" }
            GradientStop { position: 1.0; color: "#14161e" }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(480, page.width - 64)
        spacing: 0

        // Hat icon
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "🎩"
            font.pixelSize: 80
        }

        // Title
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 20
            text: "Welcome to Magic Hat"
            color: "#eaeaea"
            font.pixelSize: 32
            font.weight: Font.Light
        }

        // Subtitle
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            Layout.bottomMargin: 48
            text: "Your Familiar AI desktop is almost ready.\nThis takes about two minutes."
            color: "#6b7280"
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.5
        }

        // Feature pills
        Flow {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 56
            spacing: 8

            Repeater {
                model: [
                    "🤖 AI Assistant",
                    "🔒 Privacy Suite",
                    "🎨 Creative Tools",
                    "🎮 Gaming Ready",
                    "💻 Dev Stack"
                ]
                delegate: Rectangle {
                    height: 28
                    width: pillText.implicitWidth + 20
                    radius: 14
                    color: "#1e2030"
                    border.color: "#3e4060"
                    border.width: 1
                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: modelData
                        color: "#9ca3af"
                        font.pixelSize: 11
                    }
                }
            }
        }

        // Get Started button
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 200
            height: 48
            radius: 10
            color: startMouse.containsPress ? "#6c7ce8" :
                   startMouse.containsMouse ? "#8b9cf8" : "#7c8cf8"
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: "Get Started  →"
                color: "white"
                font.pixelSize: 15
                font.weight: Font.SemiBold
            }

            MouseArea {
                id: startMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: applicationWindow().nextPage(profilePage)
            }
        }

        // Version note
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 20
            text: "Magic Hat Desktop · Familiar AI"
            color: "#374151"
            font.pixelSize: 10
        }
    }
}
