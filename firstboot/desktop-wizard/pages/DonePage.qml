// Magic Hat Desktop Wizard — Step 5: Done
// Final screen. Opens Familiar dashboard and removes profile.unset marker.
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

    background: Rectangle {
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#0d0f1a" }
            GradientStop { position: 1.0; color: "#14161e" }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(460, page.width - 64)
        spacing: 0

        // Celebration hat
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "🎩✨"
            font.pixelSize: 72
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            text: "Your Familiar is ready"
            color: "#eaeaea"
            font.pixelSize: 28
            font.weight: Font.SemiBold
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            Layout.bottomMargin: 36
            text: "Magic Hat Desktop is set up and running.\nClick the hat icon in your taskbar to start chatting."
            color: "#6b7280"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.6
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Summary cards
        Column {
            Layout.fillWidth: true
            spacing: 8
            Layout.bottomMargin: 40

            // What's ready
            Rectangle {
                width: parent.width; height: 52; radius: 10
                color: "#0f2a1a"; border.color: "#22c55e"; border.width: 1
                RowLayout {
                    anchors { fill: parent; margins: 16 }
                    Text { text: "✅"; font.pixelSize: 18 }
                    Column {
                        Layout.fillWidth: true
                        Text { text: "Familiar AI is running"; color: "#4ade80"; font.pixelSize: 12; font.weight: Font.SemiBold }
                        Text { text: "Dashboard at localhost:5000 · Tray icon in taskbar"; color: "#166534"; font.pixelSize: 10 }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 52; radius: 10
                color: "#1a1e3a"; border.color: "#7c8cf8"; border.width: 1
                visible: applicationWindow().selectedProfiles.indexOf("privacy_suite") >= 0
                RowLayout {
                    anchors { fill: parent; margins: 16 }
                    Text { text: "🔒"; font.pixelSize: 18 }
                    Column {
                        Layout.fillWidth: true
                        Text { text: "Privacy Suite active"; color: "#a5b4fc"; font.pixelSize: 12; font.weight: Font.SemiBold }
                        Text { text: "Pi-hole + SearXNG starting up · DNS ad blocking enabled"; color: "#4338ca"; font.pixelSize: 10 }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 52; radius: 10
                color: "#1e2030"; border.color: "#3e4060"; border.width: 1
                visible: applicationWindow().selectedProfiles.indexOf("creative_studio") >= 0 ||
                         applicationWindow().selectedProfiles.indexOf("gaming") >= 0 ||
                         applicationWindow().selectedProfiles.indexOf("dev_workstation") >= 0
                RowLayout {
                    anchors { fill: parent; margins: 16 }
                    Text { text: "⏳"; font.pixelSize: 18 }
                    Column {
                        Layout.fillWidth: true
                        Text { text: "Optional profiles installing in background"; color: "#9ca3af"; font.pixelSize: 12; font.weight: Font.SemiBold }
                        Text { text: "Apps will appear in your launcher as they finish"; color: "#4b5563"; font.pixelSize: 10 }
                    }
                }
            }
        }

        // Action buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Open Dashboard
            Rectangle {
                Layout.fillWidth: true; height: 48; radius: 10
                color: dashMouse.containsPress ? "#252745" : dashMouse.containsMouse ? "#1e2040" : "#1e2030"
                border.color: "#7c8cf8"; border.width: 1
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "🗂  Open Dashboard"; color: "#7c8cf8"; font.pixelSize: 13; font.weight: Font.SemiBold }
                MouseArea {
                    id: dashMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally("http://localhost:5000")
                }
            }

            // Start using Magic Hat
            Rectangle {
                Layout.fillWidth: true; height: 48; radius: 10
                color: doneMouse.containsPress ? "#6c7ce8" : doneMouse.containsMouse ? "#8b9cf8" : "#7c8cf8"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "Start Using Magic Hat  🎩"; color: "white"; font.pixelSize: 13; font.weight: Font.SemiBold }
                MouseArea {
                    id: doneMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: applicationWindow().finish()
                }
            }
        }
    }
}
