import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The bar icon and the remote pad. Up to three Android TVs, one driven at a
// time; ADB itself lives in Service.qml and the strip along the foot of the pad
// in SetPicker.qml.
//
//   left   = open the remote pad
//   right  = Inputs / source picker
//   middle = Home
//   scroll = volume
//
// With the pad open the keyboard drives the TV, modally: `keyMap` in
// Bindings.qml is the single definition of every binding, and typing at the TV
// is entered deliberately so that single letters are free to be controls.
//
// The icon takes the theme's urgent colour when the set is unreachable.
// adb-over-wifi drops whenever a TV sleeps, and the shim reconnects on demand,
// so "unreachable" usually means asleep rather than broken.
//
// Glyphs are literal UTF-8, not \u escapes — these are 5-hex-digit codepoints
// and QML's \u takes exactly four.
//
// A Theme, so the palette and metrics the components read as `panel.x` are
// inherited rather than repeated here; Config and Service hold the settings and
// the ADB half, and Bindings the key table.
Theme {
  id: root

  property string moduleName: "io.github.swey-l1.atv-remote"
  property var settings

  // ---- the configured sets -------------------------------------------------
  //
  // Everything read from or written back to the widget's shell.json entry
  // lives in Config.qml. What follows re-exports the parts the pad and its
  // components use, the way tvState and reprobe() front Service below.
  Config {
    id: cfg
    bar: root.bar
    moduleName: root.moduleName
    settings: root.settings
  }

  readonly property int    maxSets:     cfg.maxSets
  readonly property var    tvs:         cfg.tvs
  readonly property int    activeIndex: cfg.activeIndex
  readonly property string tvAddress:   cfg.tvAddress
  readonly property int    pollSec:     cfg.setting("pollSec", 60)

  function setting(key, fallback)     { return cfg.setting(key, fallback) }
  function appKey(slot, part)         { return cfg.appKey(slot, part) }
  function freeSlot()                 { return cfg.freeSlot() }
  function selectTv(i)                { cfg.selectTv(i) }
  function cycleTv()                  { cfg.cycleTv() }
  function writeTv(slot, label, addr) { return cfg.writeTv(slot, label, addr) }
  function addTv(label, addr)         { return cfg.addTv(label, addr) }
  function removeTv(slot)             { return cfg.removeTv(slot) }
  function writeApp(slot, label, pkg) { return cfg.writeApp(slot, label, pkg) }
  function appName(pkg)               { return cfg.appName(pkg) }
  function appNiceName(pkg)           { return cfg.appNiceName(pkg) }
  function defaultAppLabel(pkg)       { return cfg.defaultAppLabel(pkg) }

  property bool opened: false
  // "up" | "down" | "unauth" | "noadb" — noadb means adb isn't installed and
  // unauth means the set answered but nobody accepted its debugging prompt.
  // Both are distinct from a sleeping TV and each deserves its own message.
  // Not `state`: Item already has one, driving QML's own state machine. Naming
  // this one after it worked only because nothing here declares states or
  // transitions, and would collide confusingly the moment something did.
  readonly property string tvState: svc.state
  // Re-exposed so the component files can compare against names rather than
  // spell the shim's strings themselves.
  readonly property var stateName: svc.stateName
  readonly property bool online: tvState === stateName.up

  // Per-slot states, parallel to `tvs`. Only refreshed when the picker is open:
  // the poll timer probes the active set alone, so three configured TVs do not
  // mean three times the adb traffic on every tick.
  readonly property var tvStates: svc.states

  Service {
    id: svc
    address: root.tvAddress
    addresses: root.tvs.map(function (t) { return t.addr })
    pollSec: root.pollSec
  }

  implicitWidth: bar ? (bar.vertical ? bar.barSize : 24) : 24
  implicitHeight: bar ? bar.barSize : 26

  // ---- talking to the TV ---------------------------------------------------

  function sh(args) {
    if (!bar || typeof bar.run !== "function") return
    bar.run(svc.shimCmd(tvAddress, args))
  }
  function key(code) { sh("key " + code) }

  // The pad is modal, like a real remote: keys drive the TV, and typing at it is
  // something you enter deliberately. Without that, every letter would be text
  // bound for the TV's search box and none of them could be a control.
  property bool typing: false

  function startTyping() { typing = true; pad.focusEntry() }
  function stopTyping()  { typing = false; pad.focusControls() }

  function launchApp(n) { sh("app " + Util.shellQuote(setting(appKey(n, "Package"), ""))) }

  // The key table and its dispatcher; see Bindings.qml. Fronted here so the
  // components keep reading everything from `panel`.
  Bindings { id: bindings; panel: root }
  readonly property var keyHelp: bindings.keyHelp
  function hintFor(id)   { return bindings.hintFor(id) }
  function labelFor(id)  { return bindings.labelFor(id) }
  function runAction(id) { bindings.runAction(id) }
  function handleKey(ev) { return bindings.handleKey(ev) }

  // Opening always lands in control mode, so the pad behaves the same way every
  // time rather than depending on how it was left.
  onOpenedChanged: if (opened) { typing = false; Qt.callLater(pad.focusControls) }

  function open()  { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  function reprobe()    { svc.reprobe() }
  function reprobeAll() { svc.reprobeAll() }

  // ---- apps ----------------------------------------------------------------

  // Launchable packages on the active set, filled in on demand.
  readonly property var appList: svc.appList
  readonly property bool appsLoading: svc.appsLoading

  function loadApps() { svc.loadApps() }

  // The bar's tooltip PopupWindow only draws when the hovered target belongs to
  // the bar window (targetBelongsToWindow in Bar.qml), and the pad is its own
  // layer-shell window -- so every bar.showTooltip call from in here was a
  // no-op. The pad carries its own hint line instead, which has the side
  // benefit of fitting a narrow column better than a floating bubble.
  property string hoverHint: ""
  function setHint(t) { if (t !== "") hoverHint = t }
  function clearHint(t) { if (hoverHint === t) hoverHint = "" }

  function reauth(i) { if (i >= 0 && i < tvs.length) svc.reauth(tvs[i].addr) }

  PadText {
    panel: root
    anchors.centerIn: parent
    text: "󰠹"
    // Colour, not just opacity: a dimmed icon on a dark bar is easy to miss.
    color: root.online ? root.textColour : root.badColour
    opacity: root.online ? (root.opened ? 1.0 : 0.85) : 0.9
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
    onEntered: if (root.bar && root.bar.showTooltip) root.bar.showTooltip(root, svc.stateMessage[root.tvState])
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

  Pad { id: pad; panel: root }
}
