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
      out.push({ slot: i, addr: addr, label: root.setting("tv" + i + "Label", "TV " + i) })
    }
    return out
  }

  // Which set the pad is driving, kept as the slot number rather than a
  // position in `tvs`: positions shift the moment a set is removed, slots do
  // not. Seeded from settings so the pad comes back where it was left; the
  // binding is broken by the first switch, which then persists it explicitly.
  property int activeSlot: parseInt(root.setting("activeSlot", 0), 10) || 0

  // Falls back to the first configured set whenever the remembered slot is not
  // there any more -- exactly what happens after removing the set you were on.
  readonly property int activeIndex: {
    for (var ai = 0; ai < tvs.length; ai++) if (tvs[ai].slot === activeSlot) return ai
    return 0
  }
  readonly property string tvAddress: (tvs.length > activeIndex) ? tvs[activeIndex].addr : ""

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

  // The one place that knows how to invoke the shim. An empty address is
  // deliberately left off rather than exported blank: the shim falls back to the
  // first connected device only when TV_ADB_ADDR is unset, which is what makes
  // the startup probe work before the bar has injected settings.
  function shimCmd(addr, args) {
    return (addr !== "" ? "TV_ADB_ADDR=" + Util.shellQuote(addr) + " " : "")
         + Util.shellQuote(shim) + " " + args
  }

  function sh(args) {
    if (!bar || typeof bar.run !== "function") return
    bar.run(shimCmd(tvAddress, args))
  }
  function key(code) { sh("key " + code) }

  // The pad is modal, like a real remote: keys drive the TV, and typing at it is
  // something you enter deliberately. Without that, every letter would be text
  // bound for the TV's search box and none of them could be a control.
  property bool typing: false

  function startTyping() { typing = true; entry.forceActiveFocus() }
  function stopTyping()  { typing = false; keyCatcher.forceActiveFocus() }

  // Control mode. Returns true when the key was ours, so the caller can accept
  // it -- anything unclaimed falls through rather than being swallowed.
  function handleKey(ev) {
    // Alt+digit still picks a set; the unmodified digits are app shortcuts now.
    if (ev.modifiers & Qt.AltModifier) {
      if (ev.key === Qt.Key_1) { selectTv(0); return true }
      if (ev.key === Qt.Key_2) { selectTv(1); return true }
      if (ev.key === Qt.Key_3) { selectTv(2); return true }
      return false
    }
    // Both power-state keys sit behind Shift, because W and S are D-pad
    // directions now. Power especially: it is the one key here that cannot be
    // undone from this side, since a TV that is off does not answer ADB, and a
    // stray press from someone who forgot to hit T would end the session.
    if (ev.modifiers & Qt.ShiftModifier) {
      if (ev.key === Qt.Key_S) { key("KEYCODE_POWER");  return true }
      if (ev.key === Qt.Key_W) { key("KEYCODE_WAKEUP"); return true }
    }
    if (ev.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)) return false

    switch (ev.key) {
      case Qt.Key_Up:    case Qt.Key_W: key("KEYCODE_DPAD_UP");     return true
      case Qt.Key_Down:  case Qt.Key_S: key("KEYCODE_DPAD_DOWN");   return true
      case Qt.Key_Left:  case Qt.Key_A: key("KEYCODE_DPAD_LEFT");   return true
      case Qt.Key_Right: case Qt.Key_D: key("KEYCODE_DPAD_RIGHT");  return true
      case Qt.Key_Return: case Qt.Key_Enter: key("KEYCODE_DPAD_CENTER"); return true

      case Qt.Key_B: case Qt.Key_Backspace: key("KEYCODE_BACK"); return true
      case Qt.Key_H: key("KEYCODE_HOME");  return true
      case Qt.Key_M: key("KEYCODE_MENU");  return true

      case Qt.Key_P: key("KEYCODE_MEDIA_PLAY_PAUSE"); return true
      case Qt.Key_R: key("KEYCODE_MEDIA_REWIND");     return true
      case Qt.Key_F: key("KEYCODE_MEDIA_FAST_FORWARD"); return true
      case Qt.Key_BracketLeft:  key("KEYCODE_MEDIA_PREVIOUS"); return true
      case Qt.Key_BracketRight: key("KEYCODE_MEDIA_NEXT");     return true

      case Qt.Key_Minus: key("KEYCODE_VOLUME_DOWN"); return true
      case Qt.Key_Equal: case Qt.Key_Plus: key("KEYCODE_VOLUME_UP"); return true
      case Qt.Key_X:     key("KEYCODE_VOLUME_MUTE"); return true

      case Qt.Key_I: sh("inputs"); return true
      case Qt.Key_C: sh("clear");  return true

      case Qt.Key_1: sh("app " + Util.shellQuote(setting("app1Package", ""))); return true
      case Qt.Key_2: sh("app " + Util.shellQuote(setting("app2Package", ""))); return true
      case Qt.Key_3: sh("app " + Util.shellQuote(setting("app3Package", ""))); return true

      case Qt.Key_T: case Qt.Key_Slash: startTyping(); return true
      case Qt.Key_Tab: cycleTv(); return true
      case Qt.Key_Escape: case Qt.Key_Q: close(); return true
    }
    return false
  }

  // Opening always lands in control mode, so the pad behaves the same way every
  // time rather than depending on how it was left.
  onOpenedChanged: if (opened) { typing = false; Qt.callLater(keyCatcher.forceActiveFocus) }

  function open()  { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  Process {
    id: probe
    command: ["bash", "-c", root.shimCmd(root.tvAddress, "status")]
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
      cmd += "echo " + i + " $(" + shimCmd(tvs[i].addr, "status") + "); "
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

  // updateEntryInline REPLACES the entry with { id } plus whatever it is handed,
  // so any key omitted here is silently dropped from shell.json -- including the
  // app shortcuts. Always send the current settings merged with the change.
  function persist(patch) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return false
    var merged = ({})
    if (settings) for (var k in settings) if (k !== "id") merged[k] = settings[k]
    for (var q in patch) merged[q] = patch[q]
    return bar.shell.updateEntryInline(moduleName, merged)
  }

  // Lowest slot with no address, or 0 when all three are taken. Mirrors how
  // `tvs` is built, legacy tvAddress included, so the two cannot disagree.
  function freeSlot() {
    for (var i = 1; i <= 3; i++)
      if (root.setting("tv" + i + "Address", i === 1 ? root.setting("tvAddress", "") : "") === "")
        return i
    return 0
  }

  // Writing one slot, used by both the add and the rename paths.
  function writeTv(slot, label, addr) {
    if (slot < 1 || slot > 3) return false
    var a = String(addr || "").trim()
    if (a === "") return false
    // A bare IP is what people read off the TV's own network screen; adb needs
    // the port, so fill in the standard one rather than failing the write.
    if (a.indexOf(":") === -1) a += ":5555"
    var name = String(label || "").trim()
    var patch = ({})
    patch["tv" + slot + "Address"] = a
    patch["tv" + slot + "Label"] = name === "" ? ("TV " + slot) : name
    // Slot 1 can be fed by the deprecated tvAddress key. Once the tv1 pair is
    // written it is dead weight, and leaving it means two sources of truth.
    if (slot === 1) patch["tvAddress"] = ""
    return root.persist(patch)
  }

  function addTv(label, addr) {
    var slot = root.freeSlot()
    return slot === 0 ? false : root.writeTv(slot, label, addr)
  }

  function removeTv(slot) {
    if (slot < 1 || slot > 3) return false
    var patch = ({})
    patch["tv" + slot + "Label"] = ""
    patch["tv" + slot + "Address"] = ""
    // Clearing only the tv1 pair would let the deprecated key resurrect the set
    // on the next reload, which reads as the removal silently not working.
    if (slot === 1) patch["tvAddress"] = ""
    if (slot === activeSlot) {
      var next = 0
      for (var i = 0; i < tvs.length; i++) if (tvs[i].slot !== slot) { next = tvs[i].slot; break }
      activeSlot = next
      patch["activeSlot"] = next
    }
    return root.persist(patch)
  }

  // Launchable packages on the active set, filled in on demand.
  property var appList: []
  property bool appsLoading: false

  Process {
    id: appsProc
    command: ["bash", "-c", "true"]
    stdout: SplitParser {
      onRead: function(line) {
        var v = String(line).trim()
        if (v === "" || v.indexOf(".") === -1) return
        var next = root.appList.slice()
        if (next.indexOf(v) === -1) next.push(v)
        root.appList = next
      }
    }
    onExited: root.appsLoading = false
  }

  function loadApps() {
    if (appsLoading) return
    appList = []
    appsLoading = true
    appsProc.command = ["bash", "-c", shimCmd(tvAddress, "apps")]
    appsProc.running = true
  }

  // The device has no display names to give -- PackageManager hands labels to
  // apps, not to `cmd package` -- so derive something readable: drop the
  // segments nearly every package carries and keep the longest of the rest,
  // which is usually the brand. Only ever a suggestion; the label is editable.
  // Several bindings have no button to hover -- menu, fast-forward, previous and
  // next, wake, switching sets -- so the list has to exist somewhere whole.
  readonly property var keyHelp: [
    "Arrows or WASD  D-pad",
    "Enter  OK",
    "B or Bksp  Back",
    "H  Home",
    "M  Menu",
    "I  Inputs",
    "C  Clear field",
    "P  Play / pause",
    "R / F  Rew / fwd",
    "[ / ]  Prev / next",
    "- / =  Volume",
    "X  Mute",
    "Shift+W  Wake",
    "Shift+S  Power",
    "1 2 3  App shortcuts",
    "T or /  Type at TV",
    "Tab  Next TV",
    "Alt+1/2/3  Jump to TV",
    "Esc or Q  Close"
  ]

  // The bar's tooltip PopupWindow only draws when the hovered target belongs to
  // the bar window (targetBelongsToWindow in Bar.qml), and the pad is its own
  // layer-shell window -- so every bar.showTooltip call from in here was a
  // no-op. The pad carries its own hint line instead, which has the side
  // benefit of fitting a narrow column better than a floating bubble.
  property string hoverHint: ""
  function setHint(t) { if (t !== "") hoverHint = t }
  function clearHint(t) { if (hoverHint === t) hoverHint = "" }

  // Same guess, title-cased for reading. The button label derivation uppercases
  // anyway, so the casing only matters where the name is shown as prose.
  function appNiceName(pkg) {
    var n = appName(pkg)
    return n === "" ? "" : n.charAt(0).toUpperCase() + n.slice(1)
  }

  function appName(pkg) {
    var noise = ["com", "org", "net", "tv", "android", "google", "app", "apps",
                 "stable", "livingroom", "one", "main", "mobile"]
    var parts = String(pkg).split(".")
    var best = ""
    for (var i = 0; i < parts.length; i++) {
      if (noise.indexOf(parts[i].toLowerCase()) !== -1) continue
      if (parts[i].length > best.length) best = parts[i]
    }
    return best === "" ? parts[parts.length - 1] : best
  }

  function writeApp(slot, label, pkg) {
    if (slot < 1 || slot > 3 || String(pkg).trim() === "") return false
    var name = String(label || "").trim()
    var patch = ({})
    patch["app" + slot + "Package"] = String(pkg).trim()
    patch["app" + slot + "Label"] = name === ""
      ? appName(pkg).substring(0, 4).toUpperCase() : name
    return root.persist(patch)
  }

  function selectTv(i) {
    if (i < 0 || i >= tvs.length || tvs[i].slot === activeSlot) return
    activeSlot = tvs[i].slot
    root.persist({ activeSlot: activeSlot })
    reprobe()
  }
  function cycleTv() { if (tvs.length > 1) selectTv((activeIndex + 1) % tvs.length) }

  // Re-showing the prompt bounces the whole adb server, which drops the other
  // sets too -- so every state on screen is stale the moment it returns, and all
  // of them get re-probed rather than just the one we acted on.
  Process {
    id: reauthProc
    command: ["bash", "-c", "true"]
    onExited: authWatch.ticksLeft = 20
  }

  // Accepting the prompt happens on the TV, seconds after reauth has already
  // exited -- so probing once on exit just re-reads "unauth", and the poll timer
  // is a minute wide. Without this the row sits on a stale state until something
  // else forces a probe (reopening the pad, which is how this got noticed).
  // Watch briefly and often instead, and stop the moment it takes.
  Timer {
    id: authWatch
    property int ticksLeft: 0
    interval: 2000
    repeat: true
    running: ticksLeft > 0
    onTriggered: {
      ticksLeft -= 1
      root.reprobe()
      // Only the active set is worth probing this often; the others are stale
      // from the server bounce too, so they get one sweep once this settles.
      if (root.state === "up" || ticksLeft === 0) {
        ticksLeft = 0
        root.reprobeAll()
      }
    }
  }
  function reauth(i) {
    if (reauthProc.running || i < 0 || i >= tvs.length) return
    reauthProc.command = ["bash", "-c", shimCmd(tvs[i].addr, "reauth")]
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
    // Outlined while the key does something other than what its face says --
    // the shortcut buttons configure rather than launch in edit mode, and
    // nothing else on them would show that.
    property bool marked: false
    // Appended to the tooltip so the pad teaches its own key bindings: hovering
    // a button is the obvious place to ask "what key is this?".
    property string keyHint: ""
    readonly property string hintText: tip === "" ? ""
      : (keyHint === "" ? tip : tip + "  [" + keyHint + "]")

    implicitWidth: Style.space(38)
    implicitHeight: Style.space(34)
    radius: Style.cornerRadius
    border.width: k.marked ? 1 : 0
    border.color: root.bar ? root.bar.foreground : "white"
    color: ma.pressed ? Color.popups.border
         : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
         : k.marked ? Qt.rgba(1, 1, 1, 0.10)
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
      onEntered: root.setHint(k.hintText)
      onExited: root.clearHint(k.hintText)
      onClicked: if (k.onPress) k.onPress()
    }
  }

  // A full-width, left-aligned line in the picker: reads as a menu entry
  // rather than a key, which is what separates "+ Add TV" from the D-pad.
  component Action: Rectangle {
    id: ac
    property string label: ""
    property string tip: ""
    property var onPress: null

    width: root.padWidth
    height: Style.space(24)
    radius: Style.cornerRadius
    color: acMa.pressed ? Color.popups.border
         : acMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(12)
      elide: Text.ElideRight
      text: ac.label
      color: root.bar ? root.bar.foreground : "white"
      opacity: 0.72
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 10
    }

    MouseArea {
      id: acMa
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.setHint(ac.tip)
      onExited: root.clearHint(ac.tip)
      onClicked: if (ac.onPress) ac.onPress()
    }
  }

  component FormButton: Rectangle {
    id: fb
    property string label: ""
    property bool active: true
    property var onPress: null

    height: Style.space(24)
    radius: Style.cornerRadius
    opacity: fb.active ? 1.0 : 0.4
    color: fbMa.containsMouse && fb.active ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

    Text {
      anchors.centerIn: parent
      text: fb.label
      color: root.bar ? root.bar.foreground : "white"
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 9
    }

    MouseArea {
      id: fbMa
      anchors.fill: parent
      hoverEnabled: true
      onClicked: if (fb.active && fb.onPress) fb.onPress()
    }
  }

  // Same treatment as the type-at-the-TV field, minus the history handling.
  component Field: Rectangle {
    id: f
    property string placeholder: ""
    property alias text: fi.text
    function focusMe() { fi.forceActiveFocus() }

    width: root.padWidth
    height: Style.space(26)
    radius: Style.cornerRadius
    color: Qt.rgba(1, 1, 1, 0.06)
    border.width: fi.activeFocus ? 1 : 0
    border.color: root.bar ? root.bar.foreground : "white"

    TextInput {
      id: fi
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: root.bar ? root.bar.foreground : "white"
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 10
      selectByMouse: true

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: fi.text.length === 0 && !fi.activeFocus
        text: f.placeholder
        color: root.bar ? root.bar.foreground : "white"
        opacity: 0.35
        font.family: fi.font.family
        font.pixelSize: fi.font.pixelSize
      }
    }
  }

  // One line of the set picker. Its own state falls back to the active set's
  // live `state` so the row a user looks at most is never showing a stale
  // verdict from the last time the picker happened to be open.
  component TvRow: Rectangle {
    id: tr
    property int idx: 0
    property bool editMode: false
    property string trailing: ""
    property var onActivate: null
    readonly property bool isActive: idx === root.activeIndex
    readonly property string st: (root.tvStates.length > idx && root.tvStates[idx] !== "")
                                 ? root.tvStates[idx]
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
      id: leftGroup
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        id: dot
        text: tr.st === "up" ? "●" : "○"
        color: tr.st === "up" ? "#98c379"
             : tr.st === "unauth" ? "#e5c07b"
             : tr.st === "noadb" ? (root.bar && root.bar.urgent ? root.bar.urgent : "#e06c75")
             : (root.bar ? root.bar.foreground : "white")
        opacity: tr.st === "up" ? 1.0 : 0.55
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 10
      }
      // Both groups are anchored to their own edge, so nothing stops a long
      // name running under the right-hand one -- and the right-hand one grows
      // when AUTH appears. Hand the name whatever is left over and let it
      // elide, rather than letting the two collide in the unauth state.
      Text {
        width: Math.max(0, tr.width - Style.space(6) * 3 - dot.width - rightGroup.width)
        elide: Text.ElideRight
        text: root.tvs.length > tr.idx ? root.tvs[tr.idx].label : ""
        color: root.bar ? root.bar.foreground : "white"
        opacity: tr.isActive ? 1.0 : 0.72
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 10
      }
    }

    Row {
      id: rightGroup
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
          onEntered: root.setHint("Re-show the USB-debugging prompt on this TV")
          onExited: root.clearHint("Re-show the USB-debugging prompt on this TV")
          onClicked: root.reauth(tr.idx)
        }
      }

      // The AUTH button already says what the state is, and the row is only as
      // wide as the pad -- showing both squeezes the name down to "Hi…".
      Text {
        visible: tr.st !== "unauth" && !tr.editMode
        text: tr.st === "" ? "…" : tr.st
        color: root.bar ? root.bar.foreground : "white"
        opacity: 0.45
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 9
      }
      Text {
        text: tr.trailing
        color: root.bar ? root.bar.foreground : "white"
        // "edit" is an affordance, not decoration, so it carries the same weight
        // as the row's own name. The expand chevrons stay quiet.
        opacity: tr.editMode ? (tr.isActive ? 1.0 : 0.72) : 0.45
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

    // Zero-sized, and exists only to own the keyboard while the pad is in
    // control mode. A layer-shell panel still has to route keys to *something*,
    // and the text field cannot be it without swallowing every control.
    Item {
      id: keyCatcher
      width: 0
      height: 0
      Keys.onPressed: function(ev) { if (root.handleKey(ev)) ev.accepted = true }
    }

    Column {
      id: pane
      spacing: Style.space(6)

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰐥"; tip: "Power"; keyHint: "Shift+S";  onPress: function() { root.key("KEYCODE_POWER") } }
        Key { label: "INPT"; tip: "Inputs"; keyHint: "I"; onPress: function() { root.sh("inputs") } }
        Key { glyph: "󰋜"; tip: "Home"; keyHint: "H";   onPress: function() { root.key("KEYCODE_HOME") } }
      }

      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁝"; tip: "Up"; keyHint: "W or Up"; onPress: function() { root.key("KEYCODE_DPAD_UP") } }
        Item { width: Style.space(38); height: Style.space(34) }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁍"; tip: "Left"; keyHint: "A or Left"; onPress: function() { root.key("KEYCODE_DPAD_LEFT") } }
        Key { label: "OK"; tip: "Select"; keyHint: "Enter"; onPress: function() { root.key("KEYCODE_DPAD_CENTER") } }
        Key { glyph: "󰁔"; tip: "Right"; keyHint: "D or Right"; onPress: function() { root.key("KEYCODE_DPAD_RIGHT") } }
      }
      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁅"; tip: "Down"; keyHint: "S or Down"; onPress: function() { root.key("KEYCODE_DPAD_DOWN") } }
        Item { width: Style.space(38); height: Style.space(34) }
      }

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁮"; tip: "Back"; keyHint: "B or Backspace"; onPress: function() { root.key("KEYCODE_BACK") } }
        Key { glyph: "󰕿"; tip: "Volume down"; keyHint: "-"; onPress: function() { root.key("KEYCODE_VOLUME_DOWN") } }
        Key { glyph: "󰕾"; tip: "Volume up"; keyHint: "="; onPress: function() { root.key("KEYCODE_VOLUME_UP") } }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰝟"; tip: "Mute"; keyHint: "X"; onPress: function() { root.key("KEYCODE_VOLUME_MUTE") } }
        Key { glyph: "󰐊"; tip: "Play/Pause"; keyHint: "P"; onPress: function() { root.key("KEYCODE_MEDIA_PLAY_PAUSE") } }
        Key { glyph: "󰒫"; tip: "Rewind"; keyHint: "R"; onPress: function() { root.key("KEYCODE_MEDIA_REWIND") } }
      }

      Row {
        spacing: Style.space(6)
        Key {
          label: root.setting("app1Label", "NFLX")
          keyHint: "1"
          marked: picker.editing
          tip: picker.editing ? "Choose the app for this button"
                              : root.appNiceName(root.setting("app1Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(1); return }
            root.sh("app " + Util.shellQuote(root.setting("app1Package", "")))
          }
        }
        Key {
          label: root.setting("app2Label", "TUBE")
          keyHint: "2"
          marked: picker.editing
          tip: picker.editing ? "Choose the app for this button"
                              : root.appNiceName(root.setting("app2Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(2); return }
            root.sh("app " + Util.shellQuote(root.setting("app2Package", "")))
          }
        }
        Key {
          label: root.setting("app3Label", "SPFY")
          keyHint: "3"
          marked: picker.editing
          tip: picker.editing ? "Choose the app for this button"
                              : root.appNiceName(root.setting("app3Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(3); return }
            root.sh("app " + Util.shellQuote(root.setting("app3Package", "")))
          }
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
            onActiveFocusChanged: if (activeFocus) root.typing = true
            Keys.onReturnPressed: entry.send()
            Keys.onEnterPressed: entry.send()
            Keys.onUpPressed: entry.recall(1)
            Keys.onDownPressed: entry.recall(-1)
            // Escape hands the keyboard back to control mode rather than
            // closing the pad, so a mistyped search does not cost the session.
            Keys.onEscapePressed: root.stopTyping()

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
              // Doubles as the only on-screen hint that the pad is modal.
              text: "T to type\u2026"
              color: root.bar ? root.bar.foreground : "white"
              opacity: 0.35
              font.family: entry.font.family
              font.pixelSize: entry.font.pixelSize
            }
          }
        }

        Key { label: "CLR"; tip: "Clear the field on the TV"; keyHint: "C"; onPress: function() { root.sh("clear") } }
      }

      // ---- which set the pad is driving ---------------------------------
      // Bottom of the pad, so it reads as context for everything above it
      // rather than as another control. Collapsed it is a single line; expanded
      // it lists every configured set with its own reachability.
      Column {
        id: picker
        property bool expanded: false
        property bool adding: false
        // While on, clicking a row opens it for rename/remove instead of
        // switching to it. A mode rather than per-row buttons because the pad
        // is three keys wide and the rows already collide at that width.
        property bool editing: false
        property bool showKeys: false
        // Expandable when there is something to expand to: another set, or a
        // free slot to add one into.
        readonly property bool hasMore: root.tvs.length > 1 || root.freeSlot() !== 0
        spacing: Style.space(4)

        // Probing three TVs costs three adb round-trips, so it happens when the
        // list is actually being looked at rather than on every poll tick.
        onExpandedChanged: if (expanded) root.reprobeAll()

        // 0 while adding, otherwise the slot being renamed. The form is the
        // same either way; only where it writes differs.
        property int editSlot: 0
        // 0 while closed, else which shortcut button is being pointed at an app.
        property int appSlot: 0
        property string appPkg: ""
        readonly property bool appFormOpen: appSlot !== 0
        readonly property bool tvFormOpen: adding || editSlot !== 0
        // Union: used for releasing the type-at-the-TV field's focus, not for
        // deciding which form to draw.
        readonly property bool formOpen: tvFormOpen || appFormOpen
        // DELETE only exists when editing, and the row has to divide evenly.
        readonly property int buttonCount: editSlot !== 0 ? 3 : 2
        readonly property real buttonWidth:
          (root.padWidth - Style.space(6) * (buttonCount - 1)) / buttonCount

        function startAdd() {
          editSlot = 0
          nameField.text = ""
          addrField.text = ""
          adding = true
          nameField.focusMe()
        }
        function startAppEdit(slot) {
          adding = false
          editSlot = 0
          appSlot = slot
          appPkg = root.setting("app" + slot + "Package", "")
          appLabelField.text = root.setting("app" + slot + "Label", "")
          root.loadApps()
          appLabelField.focusMe()
        }
        function closeAppForm() {
          appSlot = 0
          appPkg = ""
          entry.forceActiveFocus()
        }
        function commitAppForm() {
          if (appPkg === "") return
          root.writeApp(appSlot, appLabelField.text, appPkg)
          closeAppForm()
        }

        function startEdit(i) {
          if (i < 0 || i >= root.tvs.length) return
          adding = false
          nameField.text = root.tvs[i].label
          addrField.text = root.tvs[i].addr
          editSlot = root.tvs[i].slot
          nameField.focusMe()
        }
        function closeForm() {
          adding = false
          editSlot = 0
          appSlot = 0
          entry.forceActiveFocus()
        }
        function commitForm() {
          var ok = editSlot !== 0
            ? root.writeTv(editSlot, nameField.text, addrField.text)
            : root.addTv(nameField.text, addrField.text)
          if (!ok) return
          closeForm()
          Qt.callLater(root.reprobeAll)
        }
        function deleteForm() {
          if (editSlot === 0) return
          root.removeTv(editSlot)
          closeForm()
          editing = false
          Qt.callLater(root.reprobeAll)
        }

        TvRow {
          visible: !picker.expanded && root.tvs.length > 0
          idx: root.activeIndex
          trailing: picker.hasMore ? "▸" : ""
          onActivate: function() { if (picker.hasMore) picker.expanded = true }
        }

        Repeater {
          model: picker.expanded ? root.tvs.length : 0
          TvRow {
            idx: index
            editMode: picker.editing
            trailing: picker.editing ? "edit" : (index === root.activeIndex ? "▾" : "")
            onActivate: function() {
              if (picker.editing) { picker.startEdit(index); return }
              root.selectTv(index)
              picker.expanded = false
            }
          }
        }

        // With no sets configured at all there is nothing to expand, so the add
        // row stands in for the picker entirely -- otherwise the only way to
        // get a first TV in would be to hand-edit shell.json.
        Action {
          visible: !picker.formOpen && root.freeSlot() !== 0
                   && (picker.expanded || root.tvs.length === 0)
          label: "+ Add TV"
          onPress: function() { picker.startAdd() }
        }

        Action {
          visible: !picker.formOpen && picker.expanded && root.tvs.length > 0
          label: picker.editing ? "Done" : "Edit / remove"
          onPress: function() { picker.editing = !picker.editing }
        }

        // Hover-only: there is nothing to click, it is just where the bindings
        // that have no button of their own are written down.
        Action {
          visible: !picker.formOpen && picker.expanded
          label: picker.showKeys ? "Hide shortcuts" : "Keyboard shortcuts"
          tip: picker.showKeys ? "Hide the list" : "Show every key"
          onPress: function() { picker.showKeys = !picker.showKeys }
        }

        ListView {
          visible: picker.showKeys && picker.expanded && !picker.formOpen
          width: root.padWidth
          height: Style.space(120)
          clip: true
          model: root.keyHelp
          boundsBehavior: Flickable.StopAtBounds
          // Reopening kept whatever scroll position it was left at, which shows
          // the list starting halfway down its own contents.
          onVisibleChanged: if (visible) positionViewAtBeginning()

          delegate: Text {
            width: root.padWidth
            height: Style.space(16)
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(6)
            elide: Text.ElideRight
            text: modelData
            color: root.bar ? root.bar.foreground : "white"
            opacity: 0.72
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: 9
          }
        }

        Field {
          id: nameField
          visible: picker.tvFormOpen
          placeholder: "name (e.g. Bedroom)"
          Keys.onReturnPressed: addrField.focusMe()
          Keys.onEnterPressed: addrField.focusMe()
          Keys.onEscapePressed: picker.closeForm()
        }
        Field {
          id: addrField
          visible: picker.tvFormOpen
          placeholder: "192.168.1.50  (:5555 assumed)"
          Keys.onReturnPressed: picker.commitForm()
          Keys.onEnterPressed: picker.commitForm()
          Keys.onEscapePressed: picker.closeForm()
        }
        Row {
          visible: picker.tvFormOpen
          spacing: Style.space(6)

          FormButton {
            width: picker.buttonWidth
            label: "SAVE"
            // Nothing to save without an address, and going flat says so more
            // clearly than writing a half-configured set into shell.json.
            active: addrField.text.trim() !== ""
            onPress: function() { picker.commitForm() }
          }
          FormButton {
            visible: picker.editSlot !== 0
            width: picker.buttonWidth
            label: "DELETE"
            onPress: function() { picker.deleteForm() }
          }
          FormButton {
            width: picker.buttonWidth
            label: "CANCEL"
            onPress: function() { picker.closeForm() }
          }
        }

        // ---- point a shortcut button at an app ---------------------------
        Field {
          id: appLabelField
          visible: picker.appFormOpen
          placeholder: "button label (e.g. NFLX)"
          Keys.onEscapePressed: picker.closeAppForm()
          Keys.onReturnPressed: picker.commitAppForm()
          Keys.onEnterPressed: picker.commitAppForm()
        }

        Text {
          visible: picker.appFormOpen
          width: root.padWidth
          elide: Text.ElideMiddle
          text: picker.appPkg === ""
                ? (root.appsLoading ? "reading apps from the TV\u2026" : "pick an app below")
                : picker.appPkg
          color: root.bar ? root.bar.foreground : "white"
          opacity: 0.45
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 9
        }

        // Bounded and scrolling rather than a plain Column: a TV can carry
        // dozens of launchable packages, and the pad would run off the screen.
        ListView {
          visible: picker.appFormOpen
          width: root.padWidth
          height: Style.space(150)
          clip: true
          model: root.appList
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            width: root.padWidth
            height: Style.space(22)
            radius: Style.cornerRadius
            color: appMa.pressed ? Color.popups.border
                 : appMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
                 : modelData === picker.appPkg ? Qt.rgba(1, 1, 1, 0.06)
                 : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(12)
              elide: Text.ElideRight
              text: root.appName(modelData)
              color: root.bar ? root.bar.foreground : "white"
              opacity: modelData === picker.appPkg ? 1.0 : 0.72
              font.family: root.bar ? root.bar.fontFamily : "monospace"
              font.pixelSize: 10
            }

            MouseArea {
              id: appMa
              anchors.fill: parent
              hoverEnabled: true
              // The derived name is a guess, so the real package is one hover away.
              onEntered: root.setHint(modelData)
              onExited: root.clearHint(modelData)
              onClicked: {
                picker.appPkg = modelData
                if (appLabelField.text.trim() === "")
                  appLabelField.text = root.appName(modelData).substring(0, 4).toUpperCase()
              }
            }
          }
        }

        Row {
          visible: picker.appFormOpen
          spacing: Style.space(6)

          FormButton {
            width: (root.padWidth - Style.space(6)) / 2
            label: "SAVE"
            active: picker.appPkg !== ""
            onPress: function() { picker.commitAppForm() }
          }
          FormButton {
            width: (root.padWidth - Style.space(6)) / 2
            label: "CANCEL"
            onPress: function() { picker.closeAppForm() }
          }
        }
      }

      // Whatever the pointer is on, and the key that does the same thing.
      // Fixed height, so hovering never makes the pad jump about.
      Text {
        width: root.padWidth
        height: Style.space(14)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.hoverHint
        color: root.bar ? root.bar.foreground : "white"
        opacity: 0.55
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 9
      }
    }
  }
}
