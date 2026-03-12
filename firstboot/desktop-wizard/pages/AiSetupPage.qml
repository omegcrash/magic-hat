// Magic Hat Desktop Wizard — Step 3: AI Setup
// Job class selection + optional cloud API key entry.
// Reads job classes from Familiar dashboard if available.
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

    readonly property var jobClasses: [
        { key: "helper",             icon: "🔍", label: "Helper",             desc: "Research, writing, comparisons, web search" },
        { key: "social_worker",      icon: "🤝", label: "Social Worker",      desc: "Case management, resources, crisis support" },
        { key: "business_buddy",     icon: "📊", label: "Business Buddy",     desc: "Tasks, email drafting, daily planning" },
        { key: "nonprofit_director", icon: "🏛️", label: "Nonprofit Director", desc: "Donors, grants, financials, impact tracking" },
        { key: "chef",               icon: "👨‍🍳", label: "Chef",               desc: "Recipes, menus, vendors, cost tracking" },
        { key: "artist",             icon: "🎨", label: "Artist",             desc: "Pieces, commissions, shows, client management" }
    ]

    property int selectedJobIndex: 0

    ScrollView {
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            width: page.width
            anchors { left: parent.left; right: parent.right; margins: 40 }
            spacing: 0
            topPadding: 40
            bottomPadding: 40

            Text {
                text: "What do you do?"
                color: "#eaeaea"
                font.pixelSize: 26
                font.weight: Font.SemiBold
            }
            Text {
                Layout.topMargin: 6
                Layout.bottomMargin: 24
                text: "Familiar tailors its tools and suggestions to your work. You can change this any time."
                color: "#6b7280"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Job class grid (2 columns)
            GridLayout {
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                Layout.fillWidth: true
                Layout.bottomMargin: 28

                Repeater {
                    model: page.jobClasses
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 66
                        radius: 8
                        property bool sel: page.selectedJobIndex === index
                        color: sel ? "#1a1e3a" : "#1e2030"
                        border.color: sel ? "#7c8cf8" : "#2e3050"
                        border.width: sel ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            Text { text: modelData.icon; font.pixelSize: 24 }
                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: modelData.label; color: "#eaeaea"; font.pixelSize: 13; font.weight: Font.SemiBold }
                                Text { text: modelData.desc; color: "#6b7280"; font.pixelSize: 10; wrapMode: Text.WordWrap; width: parent.width }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                page.selectedJobIndex = index
                                applicationWindow().jobClass = page.jobClasses[index].key
                            }
                        }
                    }
                }
            }

            // Optional: Gemini key (free tier)
            Text {
                Layout.bottomMargin: 8
                text: "Add a free cloud AI key (optional)"
                color: "#9ca3af"
                font.pixelSize: 12
                font.weight: Font.SemiBold
            }
            Text {
                Layout.bottomMargin: 12
                text: "Google Gemini has a free tier. Paste your key below to enable cloud routing alongside local Ollama."
                color: "#4b5563"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#252740"
                border.color: geminiField.activeFocus ? "#7c8cf8" : "#3e4060"
                border.width: geminiField.activeFocus ? 2 : 1
                Layout.bottomMargin: 28

                TextInput {
                    id: geminiField
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "AIza… (optional)"
                    color: "#eaeaea"
                    font.pixelSize: 12
                    echoMode: text.length > 0 && !showKey.checked ? TextInput.Password : TextInput.Normal
                    onTextChanged: {
                        var keys = applicationWindow().providerKeys
                        keys["gemini"] = text
                        applicationWindow().providerKeys = keys
                    }
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "AIza… (optional)"
                        color: "#4b5563"
                        font.pixelSize: 12
                        visible: parent.text.length === 0
                        enabled: false
                    }
                }
            }

            // Navigation
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 100; height: 44; radius: 8
                    color: backMouse.containsMouse ? "#252745" : "transparent"
                    border.color: "#3e4060"; border.width: 1
                    Text { anchors.centerIn: parent; text: "← Back"; color: "#9ca3af"; font.pixelSize: 13 }
                    MouseArea {
                        id: backMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: applicationWindow().pageStack.pop()
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 180; height: 44; radius: 8
                    color: nextMouse.containsPress ? "#6c7ce8" : nextMouse.containsMouse ? "#8b9cf8" : "#7c8cf8"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "Install & Continue →"; color: "white"; font.pixelSize: 13; font.weight: Font.SemiBold }
                    MouseArea {
                        id: nextMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (applicationWindow().jobClass === "")
                                applicationWindow().jobClass = page.jobClasses[page.selectedJobIndex].key
                            applicationWindow().nextPage(progressPage)
                        }
                    }
                }
            }
        }
    }
}
