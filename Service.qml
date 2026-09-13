import QtQuick
import Quickshell.Io
import qs.Commons

// Everything that shells out to the ADB shim, kept away from the pad. Same split
// tailscale and dropbox use: the half that talks to hardware is worth reading
// without five hundred lines of layout wrapped around it, and it is the half
// that can be reasoned about on its own.
//
// The caller hands in which set is active and the full list; this hands back
// reachability, the app list, and nothing else.
Item {
  id: svc

  // `addresses` is in the caller's own order, so `states` lines up index for
  // index with whatever the caller is listing.
  property string address: ""
  property var addresses: []
  property int pollSec: 60

  // The manifest declares a minimum of 10, but nothing enforces it: shell.json
  // is hand-editable and no settings UI renders that schema. A zero or a
  // negative would leave the Timer below firing on every event loop iteration,
  // spawning a probe as fast as the previous one finishes.
  readonly property int pollInterval: Math.max(10, pollSec) * 1000

  readonly property string shim: String(Qt.resolvedUrl("tv-remote")).replace(/^file:\/\//, "")

  // What the shim can report. Anything else is ignored rather than stored, so a
  // state added to the shim before the widget knows how to draw it cannot leave
  // the pad showing something it has no UI for.
  readonly property var validStates: ["up", "down", "unauth", "noadb"]

  // One of validStates, for the active set.
  property string state: "up"
  property var states: []

  property var appList: []
  property bool appsLoading: false

  // The one place that knows how to invoke the shim. An empty address is
  // deliberately left off rather than exported blank: the shim falls back to the
  // first connected device only when TV_ADB_ADDR is unset, which is what makes
  // the startup probe work before the bar has injected settings.
  function shimCmd(addr, args) {
    return (addr !== "" ? "TV_ADB_ADDR=" + Util.shellQuote(addr) + " " : "")
         + Util.shellQuote(shim) + " " + args
  }

  Process {
    id: probe
    command: ["bash", "-c", svc.shimCmd(svc.address, "status")]
    stdout: SplitParser {
      onRead: function(line) {
        var v = String(line).trim()
        if (svc.validStates.indexOf(v) !== -1) svc.state = v
      }
    }
  }

  Timer {
    id: pollTimer
    interval: svc.pollInterval
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: svc.reprobe()
  }

  function reprobe() { if (!probe.running) probe.running = true }

  // Settings arrive after the first probe has already run, so that one goes out
  // with an empty address and falls back to "first connected device". Without
  // this the verdict would stand until the next poll, up to pollSec seconds of
  // lying about which set it is talking to.
  onAddressChanged: Qt.callLater(svc.reprobe)

  // One process for every set rather than one each: the shim takes a single
  // address, so the loop lives in the shell command and each set reports back
  // as "<index> <state>".
  function probeAllScript() {
    var cmd = ""
    for (var i = 0; i < addresses.length; i++)
      cmd += "echo " + i + " $(" + shimCmd(addresses[i], "status") + "); "
    return cmd === "" ? "true" : cmd
  }

  Process {
    id: probeAll
    command: ["bash", "-c", svc.probeAllScript()]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(" ")
        if (parts.length !== 2) return
        var i = parseInt(parts[0], 10)
        if (isNaN(i) || i < 0 || i >= svc.addresses.length) return
        var next = svc.states.slice()
        while (next.length < svc.addresses.length) next.push("")
        next[i] = parts[1]
        svc.states = next
      }
    }
  }

  function reprobeAll() { if (!probeAll.running) probeAll.running = true }

  Process {
    id: appsProc
    command: ["bash", "-c", "true"]
    stdout: SplitParser {
      onRead: function(line) {
        var v = String(line).trim()
        if (v === "" || v.indexOf(".") === -1) return
        var next = svc.appList.slice()
        if (next.indexOf(v) === -1) next.push(v)
        svc.appList = next
      }
    }
    onExited: svc.appsLoading = false
  }

  function loadApps() {
    if (appsLoading) return
    appList = []
    appsLoading = true
    appsProc.command = ["bash", "-c", shimCmd(address, "apps")]
    appsProc.running = true
  }

  // Re-showing the prompt bounces the whole adb server, which drops the other
  // sets too, so every state is stale the moment it returns and all of them get
  // re-probed rather than just the one acted on.
  Process {
    id: reauthProc
    command: ["bash", "-c", "true"]
    onExited: authWatch.ticksLeft = 20
  }

  // Accepting the prompt happens on the TV, seconds after reauth has already
  // exited, so probing once on exit just re-reads "unauth" and the poll timer is
  // a minute wide. Without this the row holds a stale state until something else
  // forces a probe. Watch briefly and often instead, and stop the moment it
  // takes.
  Timer {
    id: authWatch
    property int ticksLeft: 0
    interval: 2000
    repeat: true
    running: ticksLeft > 0
    onTriggered: {
      ticksLeft -= 1
      svc.reprobe()
      // Only the active set is worth probing this often; the others are stale
      // from the server bounce too, so they get one sweep once this settles.
      if (svc.state === "up" || ticksLeft === 0) {
        ticksLeft = 0
        svc.reprobeAll()
      }
    }
  }

  function reauth(addr) {
    if (reauthProc.running || String(addr || "") === "") return
    reauthProc.command = ["bash", "-c", shimCmd(addr, "reauth")]
    reauthProc.running = true
  }
}
