import QtQuick
import qs.Commons

// The type-at-the-TV field: a Field that sends what is typed as one shim call
// and remembers the last few strings, walked with Up and Down.
Field {
  id: tf

  fontSize: 11
  // Doubles as the only on-screen hint that the pad is modal.
  placeholder: "T to type\u2026"
  // Clicking into the field is the other way in to typing mode.
  onFocusedChanged: if (focused) panel.typing = true

  // Last few typed strings, newest first. -1 means "not browsing".
  property var history: []
  property int historyIndex: -1

  onKey: function(ev) {
    switch (ev.key) {
    case Qt.Key_Return:
    case Qt.Key_Enter:  tf.send();          return true
    case Qt.Key_Up:     tf.recall(1);       return true
    case Qt.Key_Down:   tf.recall(-1);      return true
    // Escape hands the keyboard back to control mode rather than closing the
    // pad, so a mistyped search does not cost the session.
    case Qt.Key_Escape: panel.stopTyping(); return true
    }
    return false
  }

  // Walk the history: Up goes further back, Down returns toward the empty
  // field.
  function recall(step) {
    if (history.length === 0) return
    var i = historyIndex + step
    if (i < -1) i = -1
    if (i > history.length - 1) i = history.length - 1
    historyIndex = i
    text = i === -1 ? "" : history[i]
    input.cursorPosition = text.length
  }

  function remember(t) {
    var h = history.slice()
    var at = h.indexOf(t)
    if (at !== -1) h.splice(at, 1)
    h.unshift(t)
    if (h.length > 10) h = h.slice(0, 10)
    history = h
    historyIndex = -1
  }

  // One shim call, not two. bar.run() is fire-and-forget, so sending the text
  // and the ENTER as separate calls races them — the ENTER landed mid-string
  // and submitted after the first character. The trailing "enter" arg makes
  // the shim sequence them in-process.
  function send() {
    var t = text
    if (t.length === 0) return
    panel.sh("text " + Util.shellQuote(t) + " enter")
    remember(t)
    text = ""
  }
}
