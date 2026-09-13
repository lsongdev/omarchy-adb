import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar icon and the remote pad. Up to three Android TVs, one driven at a
// time; ADB itself lives in Service.qml and the strip along the foot of the pad
// in SetPicker.qml.
//
//   left   = open the remote pad
//   right  = Inputs / source picker
//   middle = Home
//   scroll = volume
//
// With the pad open the keyboard drives the TV, modally: `keyMap` below is the
// single definition of every binding, and typing at the TV is entered
// deliberately so that single letters are free to be controls.
//
// The icon takes the theme's urgent colour when the set is unreachable.
// adb-over-wifi drops whenever a TV sleeps, and the shim reconnects on demand,
// so "unreachable" usually means asleep rather than broken.
//
// Glyphs are literal UTF-8, not \u escapes — these are 5-hex-digit codepoints
// and QML's \u takes exactly four.
Item {
  id: root

  property var bar
  property string moduleName: "atv.remote"
  property var settings

  // ---- the configured sets -------------------------------------------------

  readonly property int pollSec: setting("pollSec", 60)

  // Three is the schema: tv1..tv3 in shell.json, Alt+1..3 to reach them, and
  // three slots is already more TVs than most rooms have.
  readonly property int maxSets: 3

  // Up to three sets. `tvAddress` -- the pre-1.1 single-TV key -- is honoured as
  // slot 1, so an existing shell.json keeps working untouched after an update.
  // Slots with no address are dropped rather than listed as dead entries.
  readonly property var tvs: {
    var out = []
    var legacy = root.setting("tvAddress", "")
    for (var i = 1; i <= maxSets; i++) {
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

  // ---- palette -------------------------------------------------------------

  // The pad's surfaces and status colours, named once. Every component file
  // draws with these, and a literal repeated across five files is one that
  // drifts the first time somebody adjusts it -- the AUTH button had already
  // ended up a shade brighter on hover than every other button.
  readonly property color surfaceIdle:        Qt.rgba(1, 1, 1, 0.04)
  readonly property color surfaceRaised:      Qt.rgba(1, 1, 1, 0.06)
  readonly property color surfaceButton:      Qt.rgba(1, 1, 1, 0.08)
  readonly property color surfaceHover:       Qt.rgba(1, 1, 1, 0.10)
  readonly property color surfaceButtonHover: Qt.rgba(1, 1, 1, 0.16)

  readonly property color okColour:   "#98c379"
  readonly property color warnColour: "#e5c07b"
  // Urgent comes from the theme; the literal is only a fallback for when the
  // bar has not handed one over yet.
  readonly property color badColour:  bar && bar.urgent ? bar.urgent : "#e06c75"

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
  // Not `state`: Item already has one, driving QML's own state machine. Naming
  // this one after it worked only because nothing here declares states or
  // transitions, and would collide confusingly the moment something did.
  readonly property string tvState: svc.state
  readonly property bool online: tvState === "up"

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

  function startTyping() { typing = true; entry.forceActiveFocus() }
  function stopTyping()  { typing = false; keyCatcher.forceActiveFocus() }

  // Every binding, once. Behaviour, the hover hint on a button and the line in
  // the shortcut list all read from here, so a key cannot end up doing one thing
  // and being advertised as another -- which had already happened: "+" worked as
  // volume up and appeared in no list.
  //
  // `mods` is matched exactly, so Shift+S and S, or Alt+1 and 1, are separate
  // entries and order does not matter.
  readonly property var keyMap: [
    { id: "dpadUp",    keys: [Qt.Key_W, Qt.Key_Up],          hint: "W or Up",        label: "Up",           act: function() { key("KEYCODE_DPAD_UP") } },
    { id: "dpadDown",  keys: [Qt.Key_S, Qt.Key_Down],        hint: "S or Down",      label: "Down",         act: function() { key("KEYCODE_DPAD_DOWN") } },
    { id: "dpadLeft",  keys: [Qt.Key_A, Qt.Key_Left],        hint: "A or Left",      label: "Left",         act: function() { key("KEYCODE_DPAD_LEFT") } },
    { id: "dpadRight", keys: [Qt.Key_D, Qt.Key_Right],       hint: "D or Right",     label: "Right",        act: function() { key("KEYCODE_DPAD_RIGHT") } },
    { id: "ok",        keys: [Qt.Key_Return, Qt.Key_Enter],  hint: "Enter",          label: "Select / OK",  act: function() { key("KEYCODE_DPAD_CENTER") } },
    { id: "back",      keys: [Qt.Key_B, Qt.Key_Backspace],   hint: "B or Backspace", label: "Back",         act: function() { key("KEYCODE_BACK") } },
    { id: "home",      keys: [Qt.Key_H],                     hint: "H",              label: "Home",         act: function() { key("KEYCODE_HOME") } },
    { id: "menu",      keys: [Qt.Key_M],                     hint: "M",              label: "Menu",         act: function() { key("KEYCODE_MENU") } },
    { id: "inputs",    keys: [Qt.Key_I],                     hint: "I",              label: "Inputs",       act: function() { sh("inputs") } },
    { id: "clear",     keys: [Qt.Key_C],                     hint: "C",              label: "Clear the field", act: function() { sh("clear") } },
    { id: "playPause", keys: [Qt.Key_P],                     hint: "P",              label: "Play / pause", act: function() { key("KEYCODE_MEDIA_PLAY_PAUSE") } },
    { id: "rewind",    keys: [Qt.Key_R],                     hint: "R",              label: "Rewind",       act: function() { key("KEYCODE_MEDIA_REWIND") } },
    { id: "forward",   keys: [Qt.Key_F],                     hint: "F",              label: "Fast-forward", act: function() { key("KEYCODE_MEDIA_FAST_FORWARD") } },
    { id: "previous",  keys: [Qt.Key_BracketLeft],           hint: "[",              label: "Previous",     act: function() { key("KEYCODE_MEDIA_PREVIOUS") } },
    { id: "next",      keys: [Qt.Key_BracketRight],          hint: "]",              label: "Next",         act: function() { key("KEYCODE_MEDIA_NEXT") } },
    { id: "volDown",   keys: [Qt.Key_Minus],                 hint: "-",              label: "Volume down",  act: function() { key("KEYCODE_VOLUME_DOWN") } },
    { id: "volUp",     keys: [Qt.Key_Equal, Qt.Key_Plus],    hint: "= or +",         label: "Volume up",    act: function() { key("KEYCODE_VOLUME_UP") } },
    { id: "mute",      keys: [Qt.Key_X],                     hint: "X",              label: "Mute",         act: function() { key("KEYCODE_VOLUME_MUTE") } },
    { id: "wake",      keys: [Qt.Key_W], mods: Qt.ShiftModifier, hint: "Shift+W",    label: "Wake",         act: function() { key("KEYCODE_WAKEUP") } },
    { id: "power",     keys: [Qt.Key_S], mods: Qt.ShiftModifier, hint: "Shift+S",    label: "Power",        act: function() { key("KEYCODE_POWER") } },
    { id: "app1",      keys: [Qt.Key_1],                     hint: "1",              label: "App shortcut 1", act: function() { launchApp(1) } },
    { id: "app2",      keys: [Qt.Key_2],                     hint: "2",              label: "App shortcut 2", act: function() { launchApp(2) } },
    { id: "app3",      keys: [Qt.Key_3],                     hint: "3",              label: "App shortcut 3", act: function() { launchApp(3) } },
    { id: "type",      keys: [Qt.Key_T, Qt.Key_Slash],       hint: "T or /",         label: "Type at the TV", act: function() { startTyping() } },
    { id: "nextTv",    keys: [Qt.Key_Tab],                   hint: "Tab",            label: "Next TV",      act: function() { cycleTv() } },
    { id: "tv1",       keys: [Qt.Key_1], mods: Qt.AltModifier, hint: "Alt+1",        label: "Jump to TV 1", act: function() { selectTv(0) } },
    { id: "tv2",       keys: [Qt.Key_2], mods: Qt.AltModifier, hint: "Alt+2",        label: "Jump to TV 2", act: function() { selectTv(1) } },
    { id: "tv3",       keys: [Qt.Key_3], mods: Qt.AltModifier, hint: "Alt+3",        label: "Jump to TV 3", act: function() { selectTv(2) } },
    { id: "close",     keys: [Qt.Key_Escape, Qt.Key_Q],      hint: "Esc or Q",       label: "Close",         act: function() { close() } }
  ]

  function entryFor(id) {
    for (var i = 0; i < keyMap.length; i++) if (keyMap[i].id === id) return keyMap[i]
    return null
  }
  function hintFor(id)  { var e = entryFor(id); return e ? e.hint  : "" }
  function labelFor(id) { var e = entryFor(id); return e ? e.label : "" }
  function runAction(id) { var e = entryFor(id); if (e) e.act() }

  function launchApp(n) { sh("app " + Util.shellQuote(setting("app" + n + "Package", ""))) }

  // The shortcut list, written once by the same table.
  readonly property var keyHelp: keyMap.map(function (e) { return e.hint + "  " + e.label })

  // Control mode. Returns true when the key was ours, so the caller can accept
  // it -- anything unclaimed falls through rather than being swallowed.
  function handleKey(ev) {
    // A form open means the keyboard belongs to it. Without this, typing a name
    // fires controls at the TV: "Kitchen" sends Inputs on the i and flips into
    // typing mode on the t.
    if (picker.formOpen) return picker.handleFormKey(ev)

    var mods = ev.modifiers & (Qt.ShiftModifier | Qt.ControlModifier
                               | Qt.AltModifier | Qt.MetaModifier)
    for (var i = 0; i < keyMap.length; i++) {
      var e = keyMap[i]
      if (mods !== (e.mods || 0)) continue
      if (e.keys.indexOf(ev.key) === -1) continue
      e.act()
      return true
    }
    return false
  }

  // Opening always lands in control mode, so the pad behaves the same way every
  // time rather than depending on how it was left.
  onOpenedChanged: if (opened) { typing = false; Qt.callLater(keyCatcher.forceActiveFocus) }

  function open()  { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  function reprobe()    { svc.reprobe() }
  function reprobeAll() { svc.reprobeAll() }

  // ---- writing settings back -----------------------------------------------

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
    for (var i = 1; i <= maxSets; i++)
      if (root.setting("tv" + i + "Address", i === 1 ? root.setting("tvAddress", "") : "") === "")
        return i
    return 0
  }

  // Writing one slot, used by both the add and the rename paths.
  function writeTv(slot, label, addr) {
    if (slot < 1 || slot > maxSets) return false
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
    if (slot < 1 || slot > maxSets) return false
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
    if (slot < 1 || slot > maxSets || String(pkg).trim() === "") return false
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

  function reauth(i) { if (i >= 0 && i < tvs.length) svc.reauth(tvs[i].addr) }

  Text {
    anchors.centerIn: parent
    text: "󰠹"
    // Colour, not just opacity: a dimmed icon on a dark bar is easy to miss.
    color: root.online ? (root.bar ? root.bar.foreground : "white")
                       : root.badColour
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
    onEntered: if (root.bar && root.bar.showTooltip) root.bar.showTooltip(root, root.tvState === "up" ? "TV remote"
      : root.tvState === "noadb" ? "adb not installed"
      : root.tvState === "unauth" ? "TV needs authorising — open the pad and hit AUTH" : "TV unreachable")
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
    // Naming the action is enough: the description, the shortcut shown on hover
    // and what pressing it does all come from the one table.
    property string action: ""
    property string tip: action !== "" ? root.labelFor(action) : ""
    property string keyHint: action !== "" ? root.hintFor(action) : ""
    property var onPress: null
    // Outlined while the key does something other than what its face says --
    // the shortcut buttons configure rather than launch in edit mode, and
    // nothing else on them would show that.
    property bool marked: false
    // Nothing configured behind it. Still pressable, so the hint can say why.
    property bool unset: false
    readonly property string hintText: tip === "" ? ""
      : (keyHint === "" ? tip : tip + "  [" + keyHint + "]")

    implicitWidth: Style.space(38)
    implicitHeight: Style.space(34)
    radius: Style.cornerRadius
    border.width: k.marked ? 1 : 0
    border.color: root.bar ? root.bar.foreground : "white"
    opacity: k.unset ? 0.45 : 1.0
    color: ma.pressed ? Color.popups.border
         : ma.containsMouse ? root.surfaceHover
         : k.marked ? root.surfaceHover
         : root.surfaceIdle
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
      onClicked: { if (k.onPress) k.onPress(); else if (k.action !== "") root.runAction(k.action) }
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
    // Layer-shell hands the surface keyboard focus, but Qt still needs an item
    // to make active, and it will not pick one on its own. Without this nothing
    // in the pad ever holds focus and forceActiveFocus has nothing to take it
    // from, which is why opening a form left the keyboard nowhere.
    focusTarget: keyCatcher
    contentWidth: pane.implicitWidth + padding * 2
    contentHeight: pane.implicitHeight + padding * 2

    // Zero-sized, and exists only to own the keyboard while the pad is in
    // control mode. A layer-shell panel still has to route keys to *something*,
    // and the text field cannot be it without swallowing every control.
    Item {
      id: keyCatcher
      width: 0
      height: 0
      // Whatever this does not claim goes to the open form's field. Focus alone
      // is not dependable here: the panel takes keyboard focus on demand, so
      // right after a form opens the keys can still arrive at this item.
      Keys.forwardTo: picker.activeInput ? [picker.activeInput] : []
      Keys.onPressed: function(ev) { if (root.handleKey(ev)) ev.accepted = true }
    }

    Column {
      id: pane
      spacing: Style.space(6)

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰐥"; action: "power" }
        Key { label: "INPT"; action: "inputs" }
        Key { glyph: "󰋜"; action: "home" }
      }

      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁝"; action: "dpadUp" }
        Item { width: Style.space(38); height: Style.space(34) }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁍"; action: "dpadLeft" }
        Key { label: "OK"; action: "ok" }
        Key { glyph: "󰁔"; action: "dpadRight" }
      }
      Row {
        spacing: Style.space(6)
        Item { width: Style.space(38); height: Style.space(34) }
        Key { glyph: "󰁅"; action: "dpadDown" }
        Item { width: Style.space(38); height: Style.space(34) }
      }

      Row {
        spacing: Style.space(6)
        Key { glyph: "󰁮"; action: "back" }
        Key { glyph: "󰕿"; action: "volDown" }
        Key { glyph: "󰕾"; action: "volUp" }
      }
      Row {
        spacing: Style.space(6)
        Key { glyph: "󰝟"; action: "mute" }
        Key { glyph: "󰐊"; action: "playPause" }
        Key { glyph: "󰒫"; action: "rewind" }
      }

      Row {
        spacing: Style.space(6)
        Key {
          // The fallback label matches the manifest default rather than naming
          // an app nobody configured: a fresh install used to show NFLX on a
          // button with no package behind it.
          label: root.setting("app1Label", "APP1")
          action: "app1"
          marked: picker.editing
          unset: !picker.editing && root.setting("app1Package", "") === ""
          tip: picker.editing ? "Choose the app for this button"
             : root.setting("app1Package", "") === ""
               ? "Nothing set yet. Use Edit / remove to pick an app"
               : root.appNiceName(root.setting("app1Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(1); return }
            root.launchApp(1)
          }
        }
        Key {
          // The fallback label matches the manifest default rather than naming
          // an app nobody configured: a fresh install used to show NFLX on a
          // button with no package behind it.
          label: root.setting("app2Label", "APP2")
          action: "app2"
          marked: picker.editing
          unset: !picker.editing && root.setting("app2Package", "") === ""
          tip: picker.editing ? "Choose the app for this button"
             : root.setting("app2Package", "") === ""
               ? "Nothing set yet. Use Edit / remove to pick an app"
               : root.appNiceName(root.setting("app2Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(2); return }
            root.launchApp(2)
          }
        }
        Key {
          // The fallback label matches the manifest default rather than naming
          // an app nobody configured: a fresh install used to show NFLX on a
          // button with no package behind it.
          label: root.setting("app3Label", "APP3")
          action: "app3"
          marked: picker.editing
          unset: !picker.editing && root.setting("app3Package", "") === ""
          tip: picker.editing ? "Choose the app for this button"
             : root.setting("app3Package", "") === ""
               ? "Nothing set yet. Use Edit / remove to pick an app"
               : root.appNiceName(root.setting("app3Package", ""))
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(3); return }
            root.launchApp(3)
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
          color: root.surfaceRaised
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

        Key { label: "CLR"; action: "clear" }
      }

      SetPicker {
        id: picker
        panel: root
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
