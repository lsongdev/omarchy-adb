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
  readonly property string tvAddress: setting("tvAddress", "")
  readonly property int pollSec: setting("pollSec", 60)

  function setting(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  property bool opened: false
  // "up" | "down" | "noadb" — noadb means adb isn't installed, which is a
  // different problem from a sleeping TV and deserves its own message.
  property string state: "up"
  readonly property bool online: state === "up"

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
        if (v === "up" || v === "down" || v === "noadb") root.state = v
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
      : root.state === "noadb" ? "adb not installed" : "TV unreachable")
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
    }
  }
}
