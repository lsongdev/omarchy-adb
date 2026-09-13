import QtQuick
import qs.Commons

// One line of the set picker. Its own state falls back to the active set's
// live `state` so the row a user looks at most is never showing a stale
// verdict from the last time the picker happened to be open.
Rectangle {
  // The Panel this belongs to: everything it draws is themed from
  // panel.bar, and hovering reports through panel.setHint.
  property var panel: null
  id: tr
  property int idx: 0
  property bool editMode: false
  property string trailing: ""
  property var onActivate: null
  readonly property bool isActive: idx === panel.activeIndex
  readonly property string st: (panel.tvStates.length > idx && panel.tvStates[idx] !== "")
                               ? panel.tvStates[idx]
                               : (isActive ? panel.tvState : "")

  width: panel.padWidth
  height: Style.space(24)
  radius: Style.cornerRadius
  color: trMa.pressed ? Color.popups.border
       : trMa.containsMouse ? panel.surfaceHover
       : tr.isActive ? panel.surfaceRaised
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
      color: tr.st === "up" ? panel.okColour
           : tr.st === "unauth" ? panel.warnColour
           : tr.st === "noadb" ? panel.badColour
           : (panel.bar ? panel.bar.foreground : "white")
      opacity: tr.st === "up" ? 1.0 : 0.55
      font.family: panel.bar ? panel.bar.fontFamily : "monospace"
      font.pixelSize: 10
    }
    // Both groups are anchored to their own edge, so nothing stops a long
    // name running under the right-hand one -- and the right-hand one grows
    // when AUTH appears. Hand the name whatever is left over and let it
    // elide, rather than letting the two collide in the unauth state.
    Text {
      width: Math.max(0, tr.width - Style.space(6) * 3 - dot.width - rightGroup.width)
      elide: Text.ElideRight
      text: panel.tvs.length > tr.idx ? panel.tvs[tr.idx].label : ""
      color: panel.bar ? panel.bar.foreground : "white"
      opacity: tr.isActive ? 1.0 : 0.72
      font.family: panel.bar ? panel.bar.fontFamily : "monospace"
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
      color: authMa.containsMouse ? panel.surfaceButtonHover : panel.surfaceButton
      Text {
        anchors.centerIn: parent
        text: "AUTH"
        color: panel.bar ? panel.bar.foreground : "white"
        font.family: panel.bar ? panel.bar.fontFamily : "monospace"
        font.pixelSize: 8
      }
      MouseArea {
        id: authMa
        anchors.fill: parent
        hoverEnabled: true
        onEntered: panel.setHint("Re-show the USB-debugging prompt on this TV")
        onExited: panel.clearHint("Re-show the USB-debugging prompt on this TV")
        onClicked: panel.reauth(tr.idx)
      }
    }

    // The AUTH button already says what the state is, and the row is only as
    // wide as the pad -- showing both squeezes the name down to "Hi…".
    Text {
      visible: tr.st !== "unauth" && !tr.editMode
      text: tr.st === "" ? "…" : tr.st
      color: panel.bar ? panel.bar.foreground : "white"
      opacity: 0.45
      font.family: panel.bar ? panel.bar.fontFamily : "monospace"
      font.pixelSize: 9
    }
    Text {
      text: tr.trailing
      color: panel.bar ? panel.bar.foreground : "white"
      // "edit" is an affordance, not decoration, so it carries the same weight
      // as the row's own name. The expand chevrons stay quiet.
      opacity: tr.editMode ? (tr.isActive ? 1.0 : 0.72) : 0.45
      font.family: panel.bar ? panel.bar.fontFamily : "monospace"
      font.pixelSize: 9
    }
  }
}
