// Magic Hat Desktop Wizard — Step 4: Installing
// Runs profile-install.sh and streams log output.
// Saves selected profiles + job class to /etc/magichat/.
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

    property bool started: false
    property bool done: false
    property var logLines: []
    property int stepsDone: 0
    property int stepsTotal: 0

    // Steps shown in the UI (populated from selected profiles)
    property var steps: []

    Component.onCompleted: {
        buildSteps()
        Qt.callLater(startInstall)
    }

    function buildSteps() {
        var win = applicationWindow()
        var stepList = []
        var profileLabels = {
            "ai_companion":    "AI Companion",
            "privacy_suite":   "Privacy Suite",
            "creative_studio": "Creative Studio",
            "gaming":          "Gaming",
            "dev_workstation": "Dev Workstation"
        }
        stepList.push({ label: "Writing configuration", done: false, active: false })
        for (var i = 0; i < win.selectedProfiles.length; i++) {
            var key = win.selectedProfiles[i]
            if (profileLabels[key])
                stepList.push({ label: "Installing " + profileLabels[key], done: false, active: false })
        }
        stepList.push({ label: "Activating Familiar AI", done: false, active: false })
        page.steps = stepList
        page.stepsTotal = stepList.length
    }

    function startInstall() {
        var win = applicationWindow()
        page.started = true

        // Write selected profiles + job class to /etc/magichat/
        var optIn = win.selectedProfiles.filter(function(p) {
            return p !== "ai_companion" && p !== "privacy_suite"
        })

        // Construct the command: write config then run profile-install.sh
        var configCmds = [
            "mkdir -p /etc/magichat",
            "echo '" + win.jobClass + "' > /etc/magichat/job-class.conf",
        ]

        if (optIn.length > 0)
            configCmds.push("printf '" + optIn.join("\\n") + "\\n' > /etc/magichat/selected-profiles")

        var geminiKey = win.providerKeys["gemini"] || ""
        if (geminiKey) {
            configCmds.push(
                "mkdir -p /etc/magichat && " +
                "echo 'GEMINI_API_KEY=" + geminiKey + "' >> /etc/magichat/providers.env"
            )
        }

        var fullCmd = configCmds.join(" && ")
        if (optIn.length > 0)
            fullCmd += " && /opt/magichat/scripts/profiles/profile-install.sh " + optIn.join(" ")

        installProcess.command = ["bash", "-c", fullCmd]
        installProcess.start()

        // Advance first step
        advanceStep()
    }

    function advanceStep() {
        var steps = page.steps.slice()
        // Mark previous active as done
        for (var i = 0; i < steps.length; i++) {
            if (steps[i].active) {
                steps[i].active = false
                steps[i].done = true
                page.stepsDone++
                // Activate next
                if (i + 1 < steps.length) steps[i + 1].active = true
                break
            }
            if (!steps[i].done && !steps[i].active) {
                steps[i].active = true
                break
            }
        }
        page.steps = steps
    }

    // Step advance timer (visual pacing, independent of actual install)
    Timer {
        id: stepTimer
        interval: 2200
        repeat: true
        running: page.started && !page.done
        onTriggered: {
            if (page.stepsDone < page.stepsTotal - 1)
                page.advanceStep()
        }
    }

    Process {
        id: installProcess
        onReadyReadStandardOutput: {
            var lines = page.logLines.slice()
            lines.push(readAllStandardOutput().trim())
            if (lines.length > 80) lines = lines.slice(-80)
            page.logLines = lines
            logView.contentY = logView.contentHeight
        }
        onFinished: function(exitCode) {
            // Complete remaining steps
            var steps = page.steps.slice()
            for (var i = 0; i < steps.length; i++) {
                steps[i].done = true
                steps[i].active = false
            }
            page.steps = steps
            page.stepsDone = page.stepsTotal
            page.done = true
            stepTimer.stop()
            applicationWindow().installComplete = (exitCode === 0)
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 40 }
        spacing: 0

        Text {
            text: page.done ? "All done! 🎉" : "Setting up your desktop…"
            color: "#eaeaea"
            font.pixelSize: 26
            font.weight: Font.SemiBold
            Layout.bottomMargin: 28
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 32

            // Step list (left)
            Column {
                spacing: 12
                width: 220

                Repeater {
                    model: page.steps
                    delegate: RowLayout {
                        spacing: 10
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: modelData.done    ? "#22c55e" :
                                   modelData.active  ? "#7c8cf8" : "#1e2030"
                            border.color: modelData.done   ? "#22c55e" :
                                          modelData.active ? "#7c8cf8" : "#3e4060"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.done ? "✓" : (modelData.active ? "…" : "")
                                color: "white"; font.pixelSize: 10; font.weight: Font.Bold
                            }
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: modelData.active && !page.done
                                NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            text: modelData.label
                            color: modelData.done   ? "#4ade80" :
                                   modelData.active ? "#eaeaea" : "#4b5563"
                            font.pixelSize: 12
                            font.weight: modelData.active ? Font.SemiBold : Font.Normal
                        }
                    }
                }
            }

            // Log output (right)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0d0f1a"
                radius: 8
                border.color: "#1e2030"
                clip: true

                ScrollView {
                    id: logView
                    anchors { fill: parent; margins: 12 }

                    Column {
                        spacing: 2
                        Repeater {
                            model: page.logLines
                            Text {
                                text: modelData
                                color: modelData.indexOf("ERROR") >= 0 ? "#f87171" :
                                       modelData.indexOf("WARNING") >= 0 ? "#fbbf24" :
                                       modelData.indexOf("Done") >= 0 ? "#4ade80" : "#6b7280"
                                font.pixelSize: 10
                                font.family: "JetBrains Mono, monospace"
                                wrapMode: Text.WrapAnywhere
                                width: logView.width
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

        // Progress bar
        Rectangle {
            Layout.fillWidth: true
            height: 4
            radius: 2
            color: "#1e2030"
            Layout.bottomMargin: 24

            Rectangle {
                width: parent.width * (page.stepsTotal > 0 ? page.stepsDone / page.stepsTotal : 0)
                height: parent.height
                radius: parent.radius
                color: page.done ? "#22c55e" : "#7c8cf8"
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        // Continue button (enabled when done)
        Rectangle {
            Layout.alignment: Qt.AlignRight
            width: 160; height: 44; radius: 8
            enabled: page.done
            opacity: page.done ? 1.0 : 0.4
            Behavior on opacity { NumberAnimation { duration: 300 } }
            color: nextMouse.containsPress ? "#6c7ce8" : nextMouse.containsMouse ? "#8b9cf8" : "#7c8cf8"
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: "Continue →"; color: "white"; font.pixelSize: 13; font.weight: Font.SemiBold }
            MouseArea {
                id: nextMouse; anchors.fill: parent; hoverEnabled: true; enabled: page.done
                cursorShape: Qt.PointingHandCursor
                onClicked: applicationWindow().nextPage(donePage)
            }
        }
    }
}
