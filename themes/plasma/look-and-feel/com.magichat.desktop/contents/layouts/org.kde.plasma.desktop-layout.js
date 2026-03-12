// Magic Hat — KDE Plasma Desktop Layout
// Defines the default panel geometry shipped to every new user account.
// Panel: bottom taskbar with KickOff on the left, window list in the centre,
// and Familiar + network + volume + clock in the system tray on the right.
//
// Copyright (c) 2026 George Scott Foley — MIT License

var panel = new Panel;
panel.location = "bottom";
panel.height = 44;
panel.hiding = "none";

// ── Application launcher (KickOff) ────────────────────────────────────────────
panel.addWidget("org.kde.plasma.kickoff");

// ── Task manager (open windows) ───────────────────────────────────────────────
var tasks = panel.addWidget("org.kde.plasma.taskmanager");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "");
tasks.writeConfig("showOnlyCurrentDesktop", "false");
tasks.writeConfig("showOnlyCurrentActivity", "true");
tasks.writeConfig("groupingStrategy", "1");   // group by app
tasks.writeConfig("sortingStrategy", "1");    // sort by desktop

// ── Spacer ─────────────────────────────────────────────────────────────────────
panel.addWidget("org.kde.plasma.panelspacer");

// ── System tray ───────────────────────────────────────────────────────────────
var tray = panel.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
// Always-visible items: Familiar first, then standard status indicators
tray.writeConfig("extraItems",
    "com.magichat.familiar," +
    "org.kde.plasma.networkmanagement," +
    "org.kde.plasma.volume," +
    "org.kde.plasma.bluetooth");
tray.writeConfig("knownItems",
    "com.magichat.familiar," +
    "org.kde.plasma.networkmanagement," +
    "org.kde.plasma.volume," +
    "org.kde.plasma.bluetooth," +
    "org.kde.plasma.battery," +
    "org.kde.plasma.notifications," +
    "org.kde.plasma.clipboard");
tray.writeConfig("PreloadWeight", "100");

// ── Digital clock ─────────────────────────────────────────────────────────────
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", "true");
clock.writeConfig("showSeconds", "false");
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("use24hFormat", "false");

// ── Desktop (folder view / activities) ────────────────────────────────────────
var desktop = new Panel;
desktop.type = "Desktop";
desktop.formFactor = "Planar";
desktop.addWidget("org.kde.plasma.folder");
