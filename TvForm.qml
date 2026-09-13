import QtQuick

// The add-or-rename form for a set: a name, an address, and SAVE / DELETE /
// CANCEL. The same form either way; `slot` says whether it is renaming an
// existing set or adding into the first free one.
//
// Keys reach it two ways, directly while a field holds focus and forwarded
// from the pad's key catcher, so `field` says which input they should go to
// and `handleKey` is the one place Return and Escape are interpreted.
Column {
  id: form

  // The Panel this belongs to: the settings writer and the typing mode.
  property var panel: null

  property bool open: false
  // 0 while adding, otherwise the slot being renamed.
  property int slot: 0
  // Which of the two fields the keys should reach. Focus is not dependable
  // inside a panel that takes keyboard focus on demand, so the form navigates
  // from here rather than from the fields.
  property int field: 0
  readonly property var activeInput: field === 0 ? nameField.input : addrField.input

  // Only the rename form has a DELETE button, so the row divides differently.
  readonly property int buttonCount: slot !== 0 ? 3 : 2
  readonly property real buttonWidth:
    (panel.padWidth - panel.gap * (buttonCount - 1)) / buttonCount

  // The picker leaves edit mode once the set being edited is gone.
  signal removed()

  visible: open
  spacing: panel.tightGap

  function start(slot, label, addr) {
    form.slot = slot
    nameField.text = label
    addrField.text = addr
    open = true
    focusField(0)
  }

  // Both the forwarding target and the visible focus move together, so it
  // does not matter which route the next key takes.
  function focusField(n) {
    field = n
    var f = n === 0 ? nameField : addrField
    f.focusMe()
  }

  function handleKey(ev) {
    if (ev.key === Qt.Key_Escape) { close(); return true }
    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
      if (field === 0) focusField(1)
      else commit()
      return true
    }
    return false
  }

  function close() {
    open = false
    slot = 0
    panel.stopTyping()
  }
  // After a write that changed the sets: the states are stale until re-probed.
  function closeAndReprobe() {
    close()
    Qt.callLater(panel.reprobeAll)
  }

  function commit() {
    var ok = slot !== 0
      ? panel.writeTv(slot, nameField.text, addrField.text)
      : panel.addTv(nameField.text, addrField.text)
    if (ok) closeAndReprobe()
  }
  function remove() {
    if (slot === 0) return
    panel.removeTv(slot)
    removed()
    closeAndReprobe()
  }

  Field {
    id: nameField
    panel: form.panel
    placeholder: "name (e.g. Bedroom)"
    onKey: function(ev) { return form.handleKey(ev) }
  }
  Field {
    id: addrField
    panel: form.panel
    placeholder: "192.168.1.50  (:5555 assumed)"
    onKey: function(ev) { return form.handleKey(ev) }
  }
  Row {
    spacing: panel.gap

    FormButton {
      panel: form.panel
      width: form.buttonWidth
      label: "SAVE"
      // Nothing to save without an address, and going flat says so more
      // clearly than writing a half-configured set into shell.json.
      active: addrField.text.trim() !== ""
      onPress: function() { form.commit() }
    }
    FormButton {
      panel: form.panel
      visible: form.slot !== 0
      width: form.buttonWidth
      label: "DELETE"
      onPress: function() { form.remove() }
    }
    FormButton {
      panel: form.panel
      width: form.buttonWidth
      label: "CANCEL"
      onPress: function() { form.close() }
    }
  }
}
