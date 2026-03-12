// Magic Hat — Native Desktop Setup Wizard
// Kirigami-based first-run wizard for the desktop ISO track.
// Launched once by magichat-desktop-wizard.service on first graphical login.
// Removes /etc/magichat/profile.unset on completion.
//
// Run: qml /opt/magichat/firstboot/desktop-wizard/main.qml
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: "Magic Hat Setup"
    width: 760
    height: 540
    minimumWidth: 680
    minimumHeight: 480
    // No window frame chrome — we draw our own header
    flags: Qt.FramelessWindowHint | Qt.Window

    // Centre on screen
    x: (Screen.width  - width)  / 2
    y: (Screen.height - height) / 2

    // ── Theme overrides ────────────────────────────────────────────────────
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    // ── Shared wizard state ────────────────────────────────────────────────
    property var selectedProfiles: ["ai_companion", "privacy_suite"]
    property string jobClass: ""
    property var providerKeys: ({})
    property bool installComplete: false
    property var installResults: []

    // ── Page stack ─────────────────────────────────────────────────────────
    pageStack.initialPage: welcomePage
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.defaultColumnWidth: root.width

    Component { id: welcomePage;   pages/WelcomePage.qml   {} }
    Component { id: profilePage;   pages/ProfilePage.qml   {} }
    Component { id: aiSetupPage;   pages/AiSetupPage.qml   {} }
    Component { id: progressPage;  pages/ProgressPage.qml  {} }
    Component { id: donePage;      pages/DonePage.qml      {} }

    // ── Navigation helpers ─────────────────────────────────────────────────
    function nextPage(page) {
        pageStack.push(page)
    }
    function finish() {
        // Remove the profile.unset marker so wizard doesn't fire again
        finishProcess.start()
    }

    Process {
        id: finishProcess
        command: ["bash", "-c",
            "rm -f /etc/magichat/profile.unset; " +
            "systemctl --user enable familiar-briefing.timer 2>/dev/null; true"]
        onFinished: Qt.quit()
    }
}
