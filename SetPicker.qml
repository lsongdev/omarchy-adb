import QtQuick

// The strip along the foot of the pad. Four things share it, one at a time:
// the configured sets and their reachability, the add/rename form (TvForm),
// the app chooser for the three shortcut buttons (AppChooser), and the list
// of keyboard shortcuts.
//
// It sits at the bottom so it reads as context for the remote above it rather
// than as more controls. Collapsed it is a single line naming the set being
// driven; expanded it lists every set, and edit mode turns a click on a row
// into a rename rather than a switch.
//
// Keys arrive from the Panel rather than through focus: the pad is a
// layer-shell surface that takes keyboard focus on demand, so `activeInput`
// says where they should go.
Column {
  id: picker

  // The Panel this belongs to: the sets, the settings writer, the shim and the
  // hint line all live there.
  property var panel: null

  property bool expanded: false
  // While on, clicking a row opens it for rename/remove instead of
  // switching to it. A mode rather than per-row buttons because the pad
  // is three keys wide and the rows already collide at that width.
  property bool editing: false
  property bool showKeys: false
  // Expandable when there is something to expand to: another set, or a
  // free slot to add one into.
  readonly property bool hasMore: panel.tvs.length > 1 || panel.freeSlot() !== 0
  spacing: panel.tightGap

  // Probing three TVs costs three adb round-trips, so it happens when the
  // list is actually being looked at rather than on every poll tick.
  onExpandedChanged: if (expanded) panel.reprobeAll()

  // Only one form is ever open. `formOpen` hides the rows behind it and
  // releases the type-at-the-TV field; `activeInput` is where the pad should
  // forward keys meanwhile.
  readonly property bool formOpen: tvForm.open || appForm.open
  readonly property var activeInput: appForm.open ? appForm.activeInput
                                   : tvForm.open ? tvForm.activeInput : null

  // Every key a form sees comes through here, whether the field holds focus or
  // keyCatcher forwards it. Returns true when the key was the form's.
  function handleFormKey(ev) {
    return appForm.open ? appForm.handleKey(ev)
         : tvForm.open ? tvForm.handleKey(ev) : false
  }

  function startAdd() {
    if (appForm.open) appForm.close()
    tvForm.start(0, "", "")
  }
  function startEdit(i) {
    if (i < 0 || i >= panel.tvs.length) return
    if (appForm.open) appForm.close()
    tvForm.start(panel.tvs[i].slot, panel.tvs[i].label, panel.tvs[i].addr)
  }
  // Reached from the shortcut buttons above the picker while in edit mode.
  function startAppEdit(slot) {
    if (tvForm.open) tvForm.close()
    appForm.start(slot)
  }

  TvRow {
    panel: picker.panel
    visible: !picker.expanded && panel.tvs.length > 0
    idx: panel.activeIndex
    trailing: picker.hasMore ? "▸" : ""
    onActivate: function() { if (picker.hasMore) picker.expanded = true }
  }

  Repeater {
    model: picker.expanded ? panel.tvs.length : 0
    TvRow {
      panel: picker.panel
      idx: index
      editMode: picker.editing
      trailing: picker.editing ? "edit" : (index === panel.activeIndex ? "▾" : "")
      onActivate: function() {
        if (picker.editing) { picker.startEdit(index); return }
        panel.selectTv(index)
        picker.expanded = false
      }
    }
  }

  // With no sets configured at all there is nothing to expand, so the add
  // row stands in for the picker entirely -- otherwise the only way to
  // get a first TV in would be to hand-edit shell.json.
  Action {
    panel: picker.panel
    visible: !picker.formOpen && panel.freeSlot() !== 0
             && (picker.expanded || panel.tvs.length === 0)
    label: "+ Add TV"
    onPress: function() { picker.startAdd() }
  }

  Action {
    panel: picker.panel
    visible: !picker.formOpen && picker.expanded && panel.tvs.length > 0
    label: picker.editing ? "Done" : "Edit / remove"
    onPress: function() { picker.editing = !picker.editing }
  }

  // Hover-only: there is nothing to click, it is just where the bindings
  // that have no button of their own are written down.
  Action {
    panel: picker.panel
    visible: !picker.formOpen && picker.expanded
    label: picker.showKeys ? "Hide shortcuts" : "Keyboard shortcuts"
    tip: picker.showKeys ? "Hide the list" : "Show every key"
    onPress: function() { picker.showKeys = !picker.showKeys }
  }

  ListView {
    visible: picker.showKeys && picker.expanded && !picker.formOpen
    width: panel.padWidth
    height: panel.helpListHeight
    clip: true
    model: panel.keyHelp
    boundsBehavior: Flickable.StopAtBounds
    // Reopening kept whatever scroll position it was left at, which shows
    // the list starting halfway down its own contents.
    onVisibleChanged: if (visible) positionViewAtBeginning()

    delegate: PadText {
      panel: picker.panel
      width: panel.padWidth
      height: panel.helpRowHeight
      verticalAlignment: Text.AlignVCenter
      leftPadding: panel.inset
      elide: Text.ElideRight
      text: modelData
      opacity: 0.72
      font.pixelSize: 9
    }
  }

  TvForm {
    id: tvForm
    panel: picker.panel
    onRemoved: picker.editing = false
  }

  AppChooser {
    id: appForm
    panel: picker.panel
  }
}
