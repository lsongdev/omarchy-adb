import QtQuick
import qs.Commons

// Same treatment as the type-at-the-TV field, minus the history handling.
Rectangle {
  // The Panel this belongs to: everything it draws is themed from
  // panel.bar, and hovering reports through panel.setHint.
  property var panel: null
  id: f
  property string placeholder: ""
  property alias text: fi.text
  // The root here is a Rectangle, not a FocusScope, so its own activeFocus says
  // nothing about the input inside it.
  readonly property bool focused: fi.activeFocus
  function focusMe() { fi.forceActiveFocus() }

  width: panel.padWidth
  height: Style.space(26)
  radius: Style.cornerRadius
  color: Qt.rgba(1, 1, 1, 0.06)
  border.width: fi.activeFocus ? 1 : 0
  border.color: panel.bar ? panel.bar.foreground : "white"

  TextInput {
    id: fi
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    verticalAlignment: TextInput.AlignVCenter
    clip: true
    color: panel.bar ? panel.bar.foreground : "white"
    font.family: panel.bar ? panel.bar.fontFamily : "monospace"
    font.pixelSize: 10
    selectByMouse: true

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: fi.text.length === 0 && !fi.activeFocus
      text: f.placeholder
      color: panel.bar ? panel.bar.foreground : "white"
      opacity: 0.35
      font.family: fi.font.family
      font.pixelSize: fi.font.pixelSize
    }
  }
}
