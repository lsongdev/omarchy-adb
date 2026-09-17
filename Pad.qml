import QtQuick
import qs.Commons
import qs.Ui

// The remote pad: the key grid, the type-at-the-TV field, the set picker and
// the hint line, in a window that can hold the keyboard.
//
// KeyboardPanel, not PopupCard: PopupCard is an xdg-popup and only receives
// keys after a click routes focus through its parent surface, so a text
// field inside one never sees typing. KeyboardPanel is a layer-shell
// PanelWindow with WlrKeyboardFocus and exposes the same subset of the
// PopupCard API (anchorItem, owner, bar, open, padding, contentWidth/Height).
KeyboardPanel {
  id: pad
  // The Panel this belongs to: the key table, the shim, the theme and the
  // typing mode all live there. This is the view; it owns focus and layout.
  property var panel: null
  anchorItem: panel
  bar: panel.bar
  owner: panel
  open: panel.opened
  // Layer-shell hands the surface keyboard focus, but Qt still needs an item
  // to make active, and it will not pick one on its own. Without this nothing
  // in the pad ever holds focus and forceActiveFocus has nothing to take it
  // from, which is why opening a form left the keyboard nowhere.
  focusTarget: keyCatcher
  contentWidth: pane.implicitWidth + padding * 2
  contentHeight: pane.implicitHeight + padding * 2

  // Where the keyboard goes in each mode; the Panel flips the mode and
  // calls one of these.
  function focusEntry()    { entry.focusMe() }
  function focusControls() { keyCatcher.forceActiveFocus() }

  // Every key in the grid is a PadKey that already knows its Panel, so the
  // rows below can name a glyph and an action and nothing else.
  component Key: PadKey { panel: pad.panel }

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
    // A form open means the keyboard belongs to it. Without this, typing a
    // name fires controls at the TV: "Kitchen" sends Inputs on the i and
    // flips into typing mode on the t.
    Keys.onPressed: function(ev) {
      var ours = picker.formOpen ? picker.handleFormKey(ev) : panel.handleKey(ev)
      if (ours) ev.accepted = true
    }
  }

  Column {
    id: pane
    spacing: panel.gap

    // No toggle: the preview is part of the pad, and is turned off in
    // shell.json (`showScreen`) rather than from a button. Clicking it still
    // refreshes it immediately.
    Rectangle {
      width: panel.padWidth
      height: panel.screenVisible ? panel.screenHeight : 0
      visible: panel.screenVisible
      radius: Style.cornerRadius
      clip: true
      color: "black"

      Image {
        id: screenImage
        anchors.fill: parent
        source: panel.screenSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
      }

      PadText {
        panel: pad.panel
        anchors.centerIn: parent
        width: parent.width - panel.inset * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.pixelSize: 9
        opacity: 0.7
        visible: panel.screenSource === "" || panel.screenError !== ""
        text: panel.screenError !== "" ? panel.screenError
              : panel.screenLoading ? "Capturing screen…" : "Waiting for screen…"
      }

      HintArea {
        panel: pad.panel
        anchors.fill: parent
        hint: "Click to refresh the TV screen"
        onClicked: panel.refreshScreen()
      }
    }

    Column {
      width: panel.padWidth
      spacing: panel.gap

      // power and Input flank the D-pad's Up, Home and back flank Down,
      // so the two pairs of side keys read as part of the cross.
      Row {
        spacing: panel.gap
        Key { glyph: "󰐥"; action: "power" }
        Key { glyph: "󰁝"; action: "dpadUp" }
        Key { label: "INPT"; action: "inputs" }
      }
      Row {
        spacing: panel.gap
        Key { glyph: "󰁍"; action: "dpadLeft" }
        Key { label: "OK"; action: "ok" }
        Key { glyph: "󰁔"; action: "dpadRight" }
      }
      Row {
        spacing: panel.gap
        Key { glyph: "󰋜"; action: "home" }
        Key { glyph: "󰁅"; action: "dpadDown" }
        Key { glyph: "󰁮"; action: "back" }
      }

      Row {
        spacing: panel.gap
        Key { glyph: "󰕿"; action: "volDown" }
        Key { glyph: "󰝟"; action: "mute" }
        Key { glyph: "󰕾"; action: "volUp" }
      }
      Row {
        spacing: panel.gap
        Key { glyph: "󰒮"; action: "previous" }
        Key { glyph: "󰐊"; action: "playPause" }
        Key { glyph: "󰒭"; action: "next" }
      }

    Row {
      spacing: panel.gap
      // One key per shortcut slot. The fallback label matches the manifest
      // default rather than naming an app nobody configured: a fresh install
      // used to show NFLX on a button with no package behind it.
      Repeater {
        model: panel.maxSets
        Key {
          readonly property int slot: index + 1
          readonly property string pkg: panel.setting(panel.appKey(slot, "Package"), "")
          label: panel.setting(panel.appKey(slot, "Label"), "APP" + slot)
          action: "app" + slot
          marked: picker.editing
          unset: !picker.editing && pkg === ""
          tip: picker.editing ? "Choose the app for this button"
             : pkg === "" ? "Not set. Edit / remove picks an app"
             : panel.appNiceName(pkg)
          onPress: function() {
            if (picker.editing) { picker.startAppEdit(slot); return }
            panel.launchApp(slot)
          }
        }
      }
    }

    // ---- type into whatever field has focus on the TV -----------------
    Row {
      spacing: panel.gap

      TypeField {
        id: entry
        panel: pad.panel
        width: panel.keyWidth * 2 + panel.gap
        height: panel.keyHeight
      }

      Key { label: "CLR"; action: "clear" }
    }

    SetPicker {
      id: picker
      panel: pad.panel
    }

    // Whatever the pointer is on, and the key that does the same thing.
    // Fixed height, so hovering never makes the pad jump about. The pad is
    // only about twenty characters wide and a hint with its key in brackets
    // is often more, so the text wraps onto a second line rather than being
    // cut short with an ellipsis. Anywhere-wrapping is for package names,
    // which have no spaces to break at.
    PadText {
      panel: pad.panel
      width: panel.padWidth
      height: panel.hintHeight
      verticalAlignment: Text.AlignVCenter
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      maximumLineCount: 2
      elide: Text.ElideRight
      text: panel.hoverHint
      opacity: 0.55
      font.pixelSize: 9
    }
    }
  }
}
