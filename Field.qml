import QtQuick
import qs.Commons

// Same treatment as the type-at-the-TV field, minus the history handling.
//
// A FocusScope, not a plain Rectangle: focus given to the component has to reach
// the input inside it. With a Rectangle root, `focus: true` and
// `forceActiveFocus()` both land on the rectangle and stop there, so the field
// draws as if it were ready and every keystroke goes somewhere else.
FocusScope {
  id: f

  // The Panel this belongs to: everything it draws is themed from panel.bar.
  property var panel: null
  property string placeholder: ""
  property alias text: fi.text
  // So the pad can hand keys straight to the input when focus is not where it
  // should be; layer-shell only grants the surface focus on interaction.
  property alias input: fi

  readonly property bool focused: fi.activeFocus
  function focusMe() { fi.forceActiveFocus() }

  implicitWidth: panel.padWidth
  implicitHeight: Style.space(26)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: panel.surfaceRaised
    border.width: fi.activeFocus ? 1 : 0
    border.color: panel.bar ? panel.bar.foreground : "white"

    TextInput {
      id: fi
      // Within the scope, so focus handed to the Field arrives here.
      focus: true
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
}
