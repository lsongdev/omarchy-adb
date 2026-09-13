import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar remote for the Hisense Android TV, driven over ADB by
// ~/.config/omarchy/bar/scripts/tv-remote.
//
//   left   = open the remote pad
//   right  = Inputs / source picker
//   middle = Home
//
// Inputs uses SETUP_INPUTS rather than KEYCODE_TV_INPUT: that keycode is a
// no-op on this set, and the Hisense mixbar/kpad source panel is only
// reachable through protected broadcasts that adb cannot send.
//
// Glyphs are literal UTF-8, not \u escapes — these are 5-hex-digit
// codepoints and QML's \u takes exactly four.
//
// The icon dims when the TV is unreachable; adb-over-wifi drops when the set
// sleeps and the shim reconnects on demand.
Item {
  id: root

  property var bar
  property string moduleName: "atv.remote"
  property var settings

  // Resolved relative to this file so the plugin works wherever it is installed.
  readonly property string shim: String(Qt.resolvedUrl("tv-remote")).replace(/^file:\/\//, "")
  readonly property int pollSec: setting("pollSec", 60)

  // Up to three sets. `tvAddress` -- the pre-1.1 single-TV key -- is honoured as
  // slot 1, so an existing shell.json keeps working untouched after an update.
  // Slots with no address are dropped rather than listed as dead entries.
  readonly property var tvs: {
    var out = []
    var legacy = root.setting("tvAddress", "")
    for (var i = 1; i <= 3; i++) {
      var addr = root.setting("tv" + i + "Address", i === 1 ? legacy : "")
      if (addr === "") continue
      out.push({ addr: addr, label: root.setting("tv" + i + "Label", "TV " + i) })
    }
    return out
  }

  // Which set the pad is driving. Runtime-only: a bar widget has no way to write
  // settings back, so this returns to the first set when the shell restarts.
  property int activeTv: 0
  readonly property string tvAddress: (tvs.length > activeTv) ? tvs[activeTv].addr : ""

  readonly property int padWidth: Style.space(38) * 3 + Style.space(6) * 2

  function setting(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  property bool opened: false
  // "up" | "down" | "unauth" | "noadb" — noadb means adb isn't installed and
  // unauth means the set answered but nobody accepted its debugging prompt.
  // Both are distinct from a sleeping TV and each deserves its own message.
  property string state: "up"
  readonly property bool online: state === "up"

  // Per-slot states, parallel to `tvs`. Only refreshed when the picker is open:
  // the poll timer probes the active set alone, so three configured TVs do not
  // mean three times the adb traffic on every tick.
  property var tvStates: []

  // Last few typed strings, newest first. Up/Down in the field walks them.
  property var history: []
  property int historyIndex: -1

  function remember(t) {
    var h = history.slice()
    var at = h.indexOf(t)
    if (at !== -1) h.splice(at, 1)
    h.unshift(t)
    if (h.length > 10) h = h.slice(0, 10)
    history = h
    historyIndex = -1
  }

  implicitWidth: bar ? (bar.vertical ? bar.barSize : 24) : 24
  implicitHeight: bar ? bar.barSize : 26

  function sh(args) {
    if (!bar || typeof bar.run !== "function") return
    var env = tvAddress !== "" ? "TV_ADB_ADDR=" + Util.shellQuote(tvAddress) + " " : ""
    bar.run(env + Util.shellQuote(shim) + " " + args)
  }
  function key(code) { sh("key " + code) }

  function open()  { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  Process {
    id: probe
    command: ["bash", "-c",
      (root.tvAddress !== "" ? "TV_ADB_ADDR=" + Util.shellQuote(root.tvAddress) + " " : "")
      + Util.shellQuote(root.shim) + " status"]
    stdout: SplitParser {
      onRead: function(line) {
        var v = String(line).trim()
        if (v === "up" || v === "down" || v === "unauth" || v === "noadb") root.state = v
      }
    }
  }
  Timer {
    id: pollTimer
    interval: root.pollSec * 1000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.reprobe()
  }

  function reprobe() { if (!probe.running) probe.running = true }

  // One process for all slots rather than one each: the shim takes a single
  // address, so the loop lives in the shell command and each set reports back as
  // "<slot> <state>".
  function probeAllScript() {
    var cmd = ""
    for (var i = 0; i < tvs.length; i++)
      cmd += "echo " + i + " $(TV_ADB_ADDR=" + Util.shellQuote(tvs[i].addr) + " "
           + Util.shellQuote(shim) + " status); "
    return cmd === "" ? "true" : cmd
  }

  Process {
    id: probeAll
    command: ["bash", "-c", root.probeAllScript()]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(" ")
        if (parts.length !== 2) return
        var i = parseInt(parts[0], 10)
        if (isNaN(i) || i < 0 || i >= root.tvs.length) return
        var next = root.tvStates.slice()
        while (next.length < root.tvs.length) next.push("")
        next[i] = parts[1]
        root.tvStates = next
      }
    }
  }

  function reprobeAll() { if (!probeAll.running) probeAll.running = true }

  function selectTv(i) {
    if (i < 0 || i >= tvs.length || i === activeTv) return
    activeTv = i
    reprobe()
  }
  function cycleTv() { if (tvs.length > 1) selectTv((activeTv + 1) % tvs.length) }

  // Re-showing the prompt bounces the whole adb server, which drops the other
  // sets too -- so every state on screen is stale the moment it returns, and all
  // of them get re-probed rather than just the one we acted on.
  Process {
    id: reauthProc
    command: ["bash", "-c", "true"]
    onExited: { root.reprobe(); root.reprobeAll() }
  }
  function reauth(i) {
    if (reauthProc.running || i < 0 || i >= tvs.length) return
    reauthProc.command = ["bash", "-c",
      "TV_ADB_ADDR=" + Util.shellQuote(tvs[i].addr) + " " + Util.shellQuote(shim) + " reauth"]
    reauthProc.running = true
  }

  // The bar injects settings after the first probe has already run, so the
  // startup probe uses an empty address and falls back to "first connected
  // device". Without this the widget would show that stale verdict until the
  // next poll -- up to pollSec seconds of lying about which TV it is talking to.
  onTvAddressChanged: Qt.callLater(root.reprobe)

  Text {
    anchors.centerIn: parent
    text: "󰠹"
    // Colour, not just opacity: a dimmed icon on a dark bar is easy to miss.
    color: root.online ? (root.bar ? root.bar.foreground : "white")
                       : (root.bar && root.bar.urgent ? root.bar.urgent : "#e06c75")
    opacity: root.online ? (root.opened ? 1.0 : 0.85) : 0.9
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: 14
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  // The bar lays its own MouseArea (acceptedButtons: LeftButton) over every
  // module slot for drag-to-reorder. A MouseArea of ours claiming Right/Middle
  // competes with that for the grab, so left stays a MouseArea and the other
  // buttons use TapHandlers, which take passive grabs and are delivered
  // independently of the overlying area.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    onEntered: if (root.bar && root.bar.showTooltip) root.bar.showTooltip(root, root.state === "up" ? "TV remote"
      : root.state === "noadb" ? "adb not installed"
      : root.state === "unauth" ? "TV needs authorising — open the pad and hit AUTH" : "TV unreachable")
    onExited: if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(root)
    onClicked: root.toggle()
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.sh("inputs")
  }

  // Scroll over the icon changes TV volume, matching how the audio widget
  // behaves. WheelHandler rather than MouseArea.onWheel so it composes with
  // the bar's own drag overlay the same way the TapHandlers do.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(ev) {
      if (ev.angleDelta.y === 0) return
      root.key(ev.angleDelta.y > 0 ? "KEYCODE_VOLUME_UP" : "KEYCODE_VOLUME_DOWN")
    }
  }

  TapHandler {
    acceptedButtons: Qt.MiddleButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.key("KEYCODE_HOME")
  }

  component Key: Rectangle {
    id: k
    property string glyph: ""
    property string label: ""
    property string tip: ""
    property var onPress: null

    implicitWidth: Style.space(38)
    implicitHeight: Style.space(34)
    radius: Style.cornerRadius
    color: ma.pressed ? Color.popups.border
         : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
         : Qt.rgba(1, 1, 1, 0.04)
    Behavior on color { ColorAnimation { duration: 90 } }

    Text {
      anchors.centerIn: parent
      text: k.glyph !== "" ? k.glyph : k.label
      color: root.bar ? root.bar.foreground : "white"
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: k.glyph !== "" ? 15 : 10
    }

    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      onEntered: if (k.tip !== "" && root.bar && root.bar.showTooltip) root.bar.showTooltip(k, k.tip)
      onExited: if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(k)
      onClicked: if (k.onPress) k.onPress()
    }
  }

  // One line of the set picker. Its own state falls back to the active set's
  // live `state` so the row a user looks at most is never showing a stale
  // verdict from the last time the picker happened to be open.
  component TvRow: Rectangle {
    id: tr
    property int slot: 0
    property string trailing: ""
    property var onActivate: null
    readonly property bool isActive: slot === root.activeTv
    readonly property string st: (root.tvStates.length > slot && root.tvStates[slot] !== "")
                                 ? root.tvStates[slot]
                                 : (isActive ? root.state : "")

    width: root.padWidth
    height: Style.space(24)
    radius: Style.cornerRadius
    color: trMa.pressed ? Color.popups.border
         : trMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
         : tr.isActive ? Qt.rgba(1, 1, 1, 0.06)
         : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    // Declared before the content so the AUTH button, a later sibling, stacks
    // above it and keeps its own clicks.
    MouseArea {
      id: trMa
      anchors.fill: parent
      hoverEnabled: true
      onClicked: if (tr.onActivate) tr.onActivate()
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        text: tr.st === "up" ? "●" : "○"
        color: tr.st === "up" ? "#98c379"
             : tr.st === "unauth" ? "#e5c07b"
             : tr.st === "noadb" ? (root.bar && root.bar.urgent ? root.bar.urgent : "#e06c75")
             : (root.bar ? root.bar.foreground : "white")
        opacity: tr.st === "up" ? 1.0 : 0.55
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 10
      }
      Text {
        text: root.tvs.length > tr.slot ? root.tvs[tr.slot].label : ""
        color: root.bar ? root.bar.foreground : "white"
        opacity: tr.isActive ? 1.0 : 0.72
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 10
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      // Offered only when it is actually the problem: an unauthorised set needs
      // someone to tap Allow on the TV, which no amount of reconnecting fixes.
      Rectangle {
        visible: tr.st === "unauth"
        width: Style.space(30)
        height: Style.space(18)
        radius: Style.cornerRadius
        color: authMa.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
        Text {
          anchors.centerIn: parent
          text: "AUTH"
          color: root.bar ? root.bar.foreground : "white"
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 8
        }
        MouseArea {
          id: authMa
          anchors.fill: parent
          hoverEnabled: true
          onEntered: if (root.bar && root.bar.showTooltip)
            root.bar.showTooltip(tr, "Re-show the USB-debugging prompt on this TV")
          onExited: if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(tr)
          onClicked: root.reauth(tr.slot)
        }
      }

      Text {
        text: tr.st === "" ? "…" : tr.st
        color: root.bar ? root.bar.foreground : "white"
        opacity: 0.45
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 9
      }
      Text {
        text: tr.trailing
        color: root.bar ? root.bar.foreground : "white"
        opacity: 0.45
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 9
      }
    }
  }

  // KeyboardPanel, not PopupCard: PopupCard is an xdg-popup and only receives
  // keys after a click routes focus through its parent surface, so a text
  // field inside one never sees typing. KeyboardPanel is a layer-shell
  // PanelWindow with WlrKeyboardFocus and exposes the same subset of the
  // PopupCard API (anchorItem, owner, bar, open, padding, contentWidth/Height).
  KeyboardPanel {
    id: pad
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: pane.implicitWidth + padding * 2
    contentHeight: pane.implicitHeight + padding * 2

    Column {
      id: pane
      spacing: Style.space(6)

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰐥"; tip: "Power";  onPress: function() { root.key("KEYCODE_POWER") } }
        Key { label: "INPT"; tip: "Inputs"; onPress: function() { root.sh("inputs") } }
        Key { glyph: "󰋜"; tip: "Home";   onPress: function() { root.key("KEYCODE_HOME") } }
      }

      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁝"; tip: "Up"; onPress: function() { root.key("KEYCODE_DPAD_UP") } }
        Item { width: Style.space(38); height: Style.space(34) }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁍"; tip: "Left"; onPress: function() { root.key("KEYCODE_DPAD_LEFT") } }
        Key { label: "OK"; tip: "Select"; onPress: function() { root.key("KEYCODE_DPAD_CENTER") } }
        Key { glyph: "󰁔"; tip: "Right"; onPress: function() { root.key("KEYCODE_DPAD_RIGHT") } }
      }
      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁅"; tip: "Down"; onPress: function() { root.key("KEYCODE_DPAD_DOWN") } }
        Item { width: Style.space(38); height: Style.space(34) }
      }

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁮"; tip: "Back"; onPress: function() { root.key("KEYCODE_BACK") } }
        Key { glyph: "󰕿"; tip: "Volume down"; onPress: function() { root.key("KEYCODE_VOLUME_DOWN") } }
        Key { glyph: "󰕾"; tip: "Volume up"; onPress: function() { root.key("KEYCODE_VOLUME_UP") } }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰝟"; tip: "Mute"; onPress: function() { root.key("KEYCODE_VOLUME_MUTE") } }
        Key { glyph: "󰐊"; tip: "Play/Pause"; onPress: function() { root.key("KEYCODE_MEDIA_PLAY_PAUSE") } }
        Key { glyph: "󰒫"; tip: "Rewind"; onPress: function() { root.key("KEYCODE_MEDIA_REWIND") } }
      }

      Row {
        spacing: Style.space(6)
        Key {
          label: root.setting("app1Label", "NFLX"); tip: root.setting("app1Package", "")
          onPress: function() { root.sh("app " + Util.shellQuote(root.setting("app1Package", ""))) }
        }
        Key {
          label: root.setting("app2Label", "TUBE"); tip: root.setting("app2Package", "")
          onPress: function() { root.sh("app " + Util.shellQuote(root.setting("app2Package", ""))) }
        }
        Key {
          label: root.setting("app3Label", "SPFY"); tip: root.setting("app3Package", "")
          onPress: function() { root.sh("app " + Util.shellQuote(root.setting("app3Package", ""))) }
        }
      }

      // ---- type into whatever field has focus on the TV -----------------
      Row {
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(38) * 2 + Style.space(6)
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: entry.activeFocus ? 1 : 0
          border.color: root.bar ? root.bar.foreground : "white"

          TextInput {
            id: entry
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: root.bar ? root.bar.foreground : "white"
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: 11
            selectByMouse: true
            focus: root.opened

            Keys.onReturnPressed: entry.send()
            Keys.onEnterPressed: entry.send()
            Keys.onUpPressed: entry.recall(1)
            Keys.onDownPressed: entry.recall(-1)

            // Switching sets has to dodge the field: plain digits are text the
            // user is typing at the TV, so the jumps take Alt. Tab has nothing
            // else to focus inside the pad, so it cycles.
            Keys.onPressed: function(ev) {
              if (ev.modifiers & Qt.AltModifier) {
                if (ev.key === Qt.Key_1) { root.selectTv(0); ev.accepted = true }
                else if (ev.key === Qt.Key_2) { root.selectTv(1); ev.accepted = true }
                else if (ev.key === Qt.Key_3) { root.selectTv(2); ev.accepted = true }
              } else if (ev.key === Qt.Key_Tab) {
                root.cycleTv()
                ev.accepted = true
              }
            }

            // Walk the history: Up goes further back, Down returns toward the
            // empty field. -1 means "not browsing".
            function recall(step) {
              if (root.history.length === 0) return
              var i = root.historyIndex + step
              if (i < -1) i = -1
              if (i > root.history.length - 1) i = root.history.length - 1
              root.historyIndex = i
              text = i === -1 ? "" : root.history[i]
              cursorPosition = text.length
            }

            // One shim call, not two. bar.run() is fire-and-forget, so sending
            // the text and the ENTER as separate calls races them — the ENTER
            // landed mid-string and submitted after the first character. The
            // trailing "enter" arg makes the shim sequence them in-process.
            function send() {
              var t = text
              if (t.length === 0) return
              root.sh("text " + Util.shellQuote(t) + " enter")
              root.remember(t)
              text = ""
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: entry.text.length === 0 && !entry.activeFocus
              text: "type\u2026"
              color: root.bar ? root.bar.foreground : "white"
              opacity: 0.35
              font.family: entry.font.family
              font.pixelSize: entry.font.pixelSize
            }
          }
        }

        Key { label: "CLR"; tip: "Clear the field on the TV"; onPress: function() { root.sh("clear") } }
      }

      // ---- which set the pad is driving ---------------------------------
      // Bottom of the pad, so it reads as context for everything above it
      // rather than as another control. Collapsed it is a single line; expanded
      // it lists every configured set with its own reachability.
      Column {
        id: picker
        property bool expanded: false
        spacing: Style.space(4)
        visible: root.tvs.length > 0

        // Probing three TVs costs three adb round-trips, so it happens when the
        // list is actually being looked at rather than on every poll tick.
        onExpandedChanged: if (expanded) root.reprobeAll()

        TvRow {
          visible: !picker.expanded
          slot: root.activeTv
          trailing: root.tvs.length > 1 ? "▸" : ""
          onActivate: function() { if (root.tvs.length > 1) picker.expanded = true }
        }

        Repeater {
          model: picker.expanded ? root.tvs.length : 0
          TvRow {
            slot: index
            trailing: index === root.activeTv ? "▾" : ""
            onActivate: function() { root.selectTv(index); picker.expanded = false }
          }
        }
      }
    }
  }
}
