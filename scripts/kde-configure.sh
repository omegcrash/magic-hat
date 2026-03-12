#!/usr/bin/env bash
# Magic Hat — KDE System-Wide Configuration
# Writes KDE defaults to /etc/skel/ so every new user account gets
# the Magic Hat look-and-feel and the Familiar applet pre-pinned.
#
# Called from kickstart %post. Safe to re-run.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

SKEL="${1:-/etc/skel}"
XDG_CONFIG="${SKEL}/.config"

echo "=== Magic Hat KDE Configure: $(date) ==="
mkdir -p "${XDG_CONFIG}"

# ── Global KDE settings ───────────────────────────────────────────────────────
cat > "${XDG_CONFIG}/kdeglobals" << 'KDEGLOBALS'
[General]
ColorScheme=MagicHat
Name=MagicHat
shadeSortColumn=true

[KDE]
AnimationDurationFactor=0.5
LookAndFeelPackage=com.magichat.desktop
SingleClick=false
widgetStyle=Breeze

[Icons]
Theme=Papirus-Dark

[Colors:Button]
BackgroundAlternate=189,195,199
BackgroundNormal=44,47,60
DecorationFocus=114,159,207
DecorationHover=114,159,207
ForegroundActive=114,159,207
ForegroundInactive=127,140,141
ForegroundNegative=231,76,60
ForegroundNeutral=241,196,15
ForegroundNormal=236,240,241
ForegroundPositive=46,204,113
ForegroundVisited=192,128,255

[Colors:View]
BackgroundAlternate=26,28,38
BackgroundNormal=20,22,30
DecorationFocus=114,159,207
DecorationHover=114,159,207
ForegroundActive=114,159,207
ForegroundInactive=127,140,141
ForegroundNegative=231,76,60
ForegroundNeutral=241,196,15
ForegroundNormal=236,240,241
ForegroundPositive=46,204,113
ForegroundVisited=192,128,255

[Colors:Window]
BackgroundAlternate=30,32,44
BackgroundNormal=26,28,38
ForegroundNormal=236,240,241

[WM]
activeBackground=26,28,38
activeBlend=26,28,38
activeForeground=236,240,241
inactiveBackground=22,24,32
inactiveBlend=22,24,32
inactiveForeground=127,140,141
KDEGLOBALS

# ── Window manager settings ───────────────────────────────────────────────────
cat > "${XDG_CONFIG}/kwinrc" << 'KWINRC'
[Compositing]
Enabled=true
OpenGLIsUnsafe=false
Backend=OpenGL
GLTextureFilter=2

[Windows]
FocusPolicy=ClickToFocus
AltTabStyle=KDE
BorderlessMaximizedWindows=false
SnapOnlyWhenOverlapping=false

[Effect-PresentWindows]
LayoutMode=1

[TabBox]
DesktopMode=0
DesktopListMode=0
KWINRC

# ── Screen locker ─────────────────────────────────────────────────────────────
cat > "${XDG_CONFIG}/kscreenlockerrc" << 'LOCKRC'
[Daemon]
Autolock=true
LockGrace=5
LockOnResume=true
Timeout=10
[Greeter]
Theme=org.kde.breeze.desktop
LOCKRC

# ── Plasma panel layout (Familiar applet pre-pinned) ─────────────────────────
# This file pre-wires the Familiar tray applet into the default panel.
# Full panel layout is defined in the look-and-feel package
# (themes/plasma/look-and-feel/com.magichat.desktop/contents/layouts/).
cat > "${XDG_CONFIG}/plasma-org.kde.plasma.desktop-appletsrc" << 'APPLETSRC'
[ActionPlugins][0]
RightButton;NoModifier=org.kde.contextmenu

[Containments][1]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][1][Applets][2]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.taskmanager

[Containments][1][Applets][3][Configuration][General]
launchers=

[Containments][1][Applets][4]
immutability=1
plugin=org.kde.plasma.systemtray

[Containments][1][Applets][4][Configuration]
PreloadWeight=100

[Containments][1][Applets][4][Configuration][General]
extraItems=com.magichat.familiar,org.kde.plasma.networkmanagement,org.kde.plasma.volume,org.kde.plasma.bluetooth
knownItems=com.magichat.familiar,org.kde.plasma.networkmanagement,org.kde.plasma.volume,org.kde.plasma.bluetooth,org.kde.plasma.battery,org.kde.plasma.notifications

[Containments][1][Applets][5]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][1][Applets][5][Configuration][Appearance]
showDate=true
showSeconds=false
dateFormat=shortDate

[Containments][1][General]
AppletOrder=2;3;4;5

[Containments][2]
activityId=
formfactor=1
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
APPLETSRC

# ── Familiar applet configuration ─────────────────────────────────────────────
mkdir -p "${XDG_CONFIG}/plasma-org.kde.plasma.desktop-appletsrc.d"
cat > "${XDG_CONFIG}/plasma-familiar-applet.conf" << 'APPLETCONF'
[familiar-applet]
dashboardUrl=http://localhost:5000
pollIntervalSeconds=30
briefingEnabled=true
briefingTime=08:00
APPLETCONF

# ── Font defaults ─────────────────────────────────────────────────────────────
cat > "${XDG_CONFIG}/kcmfonts" << 'FONTS'
[General]
fixed=JetBrains Mono,11,-1,5,50,0,0,0,0,0
font=Noto Sans,10,-1,5,50,0,0,0,0,0
menuFont=Noto Sans,10,-1,5,50,0,0,0,0,0
smallestReadableFont=Noto Sans,8,-1,5,50,0,0,0,0,0
toolBarFont=Noto Sans,10,-1,5,50,0,0,0,0,0
FONTS

# ── Input devices ─────────────────────────────────────────────────────────────
cat > "${XDG_CONFIG}/kcminputrc" << 'INPUTRC'
[Mouse]
cursorTheme=breeze_cursors
cursorSize=24
doubleClickInterval=400
INPUTRC

# ── Notifications ─────────────────────────────────────────────────────────────
cat > "${XDG_CONFIG}/plasmanotifyrc" << 'NOTIFYRC'
[Notifications]
InhibitNotificationsWhenScreensMirrored=true
PopupPosition=TopRight
PopupTimeout=8000
NOTIFYRC

# ── Install all Magic Hat themes (delegated to install-themes.sh) ─────────────
if [[ -x /opt/magichat/scripts/install-themes.sh ]]; then
    /opt/magichat/scripts/install-themes.sh /opt/magichat/themes
else
    # Inline fallback if install-themes.sh is not yet present
    if [[ -d /opt/magichat/themes/plasma/look-and-feel/com.magichat.desktop ]]; then
        kpackagetool6 --global --install \
            /opt/magichat/themes/plasma/look-and-feel/com.magichat.desktop \
            --type Plasma/LookAndFeel 2>/dev/null || \
        kpackagetool6 --global --upgrade \
            /opt/magichat/themes/plasma/look-and-feel/com.magichat.desktop \
            --type Plasma/LookAndFeel 2>/dev/null || true
    fi
    if [[ -d /opt/magichat/themes/sddm/magichat ]]; then
        cp -r /opt/magichat/themes/sddm/magichat /usr/share/sddm/themes/ 2>/dev/null || true
    fi
fi

# ── System-wide KDE defaults (XDG config) ─────────────────────────────────────
mkdir -p /etc/xdg
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group General --key ColorScheme MagicHat 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group KDE --key LookAndFeelPackage com.magichat.desktop 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group Icons --key Theme Papirus-Dark 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/ksplashrc \
    --group KSplash --key Theme com.magichat.desktop 2>/dev/null || true

# ── Default browser ───────────────────────────────────────────────────────────
mkdir -p /etc/xdg/xdg-utils
echo "firefox" > /etc/xdg/xdg-utils/browser.conf 2>/dev/null || true

# ── Firefox policies (homepage + bookmarks) ───────────────────────────────────
mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json << 'FFPOLICIES'
{
  "policies": {
    "Homepage": {
      "URL": "http://localhost:5000",
      "Locked": false,
      "StartPage": "homepage"
    },
    "NewTabPage": "about:blank",
    "DisplayBookmarksToolbar": "always",
    "ManagedBookmarks": [
      { "name": "Familiar Dashboard", "url": "http://localhost:5000" },
      { "name": "Joplin Notes", "url": "http://localhost:22300" },
      { "name": "Gitea", "url": "http://localhost:3000" },
      { "name": "Mealie Recipes", "url": "http://localhost:9925" },
      { "name": "Pi-hole Admin", "url": "http://localhost/pihole/" },
      { "name": "SearXNG Search", "url": "http://localhost:8888" },
      { "name": "Jellyfin", "url": "http://localhost:8096" },
      { "name": "Nextcloud", "url": "http://localhost:8080" }
    ],
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true
  }
}
FFPOLICIES

# ── Desktop wizard: enable as user service for new accounts ───────────────────
# The magichat-desktop-wizard.service only fires when /etc/magichat/profile.unset exists.
SKEL_SYSTEMD="${SKEL}/.config/systemd/user"
mkdir -p "${SKEL_SYSTEMD}/graphical-session.target.wants"
if [[ -f /opt/magichat/systemd/magichat-desktop-wizard.service ]]; then
    cp /opt/magichat/systemd/magichat-desktop-wizard.service \
        "${SKEL_SYSTEMD}/magichat-desktop-wizard.service"
    ln -sf "../magichat-desktop-wizard.service" \
        "${SKEL_SYSTEMD}/graphical-session.target.wants/magichat-desktop-wizard.service" \
        2>/dev/null || true
    echo "  Desktop wizard: pre-enabled in /etc/skel"
fi

# ── Briefing timer: pre-enable for new accounts ────────────────────────────────
TIMERS_WANT="${SKEL_SYSTEMD}/timers.target.wants"
mkdir -p "${TIMERS_WANT}"
for UNIT in familiar-briefing.service familiar-briefing.timer; do
    if [[ -f /opt/magichat/systemd/${UNIT} ]]; then
        cp /opt/magichat/systemd/${UNIT} "${SKEL_SYSTEMD}/${UNIT}"
    fi
done
ln -sf "../familiar-briefing.timer" "${TIMERS_WANT}/familiar-briefing.timer" 2>/dev/null || true
echo "  Briefing timer: pre-enabled in /etc/skel"

echo "=== KDE configuration complete ==="
