; =============================================================================
;  PathFinder.ahk  -  AutoHotkey v2
; -----------------------------------------------------------------------------
;  Does the input for the PathFinder addon. The addon does all the steering;
;  this only holds W, turns with mouse look, and taps Space, as the addon's
;  command dot asks. The right mouse button stays held for as long as the
;  addon is steering (not just while turning), so the camera stays behind the
;  character facing the way it walks, and a short turn is never a right-click
;  on whatever is under the cursor. Everything is released when WoW loses
;  focus, the dot shows anything it doesn't recognize, or the script exits.
;
;  The dot is one square at the top-left of the WoW window (second row, first
;  column). Each color channel is one of four levels, 0 / 85 / 170 / 255
;  (Navigator.lua in the addon folder):
;    green  0 none (let go of everything), 1 steering without W, 2 W + Space, 3 W
;    red    how hard to turn left, 0-3
;    blue   how hard to turn right, 0-3
;  A color must read the same twice in a row before it's acted on.
;
;  Smoothness: the turn speed glides toward (level / 3) * TurnSpeed with an
;  exponential ease (time constant TurnEase), so changes in level blend into
;  each other instead of stepping. The mouse moves every MouseMs, timed with
;  the high-resolution counter and with sub-pixel carry, so each move is the
;  exact distance for the time since the last one. TurnSpeed doesn't have to
;  match the game's mouse sensitivity: the addon re-reads its facing every
;  frame. Lower TurnSpeed if the view swings past the target and wobbles;
;  raise it if turns crawl. Raise TurnEase for softer, slower changes.
;
;  Start it yourself (right-click > Run script; needs AutoHotkey v2) and leave
;  it running: it idles while the dot is black, and the addon can't start
;  programs. While WoW has focus it presses HeartbeatKey (Ctrl+Alt+Shift+F9)
;  every few seconds so the addon knows it's running (AHKLink.lua); don't
;  bind that key to anything. Its tray icon tip says whether it's steering.
;
;    Ctrl+F10   exit
; =============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

; Per-monitor DPI aware, so client coordinates are physical pixels like the dot.
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
; 1 ms system timer resolution while this runs, so the mouse timer fires evenly.
DllCall("winmm\timeBeginPeriod", "UInt", 1)

global CFG := {
    ExitKey:     "^F10",
    Keys:        { forward: "w", jump: "Space" },
    TurnSpeed:   320,                             ; mouse pixels per second at turn level 3
    TurnEase:    0.15,                            ; seconds for the turn speed to cover ~63% of a change
    MouseMs:     8,                               ; how often the mouse moves
    DotSize:     4,                               ; physical pixels; MARKER_PIXELS in Navigator.lua
    PollMs:      30,
    WowExeRegex: "i)^Wow(Classic|B|T)?\.exe$",    ; retail / classic / beta / PTR clients
    HeartbeatKey: "^!+{F9}",                      ; AHKLink.lua SIGNAL_KEY; no Alt+F4 combos, ever
    HeartbeatMs: 3000,
}

global holdingKey := false      ; W held down by us
global holdingMouse := false    ; right button held down by us
global current := ""            ; reading being carried out, "" = none
global want := { forward: false, turn: 0, jump: false, steer: false }
global last := ""               ; previous reading, for the read-twice rule
global speed := 0.0             ; current turn speed, pixels per second (negative = left)
global carry := 0.0             ; fraction of a pixel not yet moved
global freq := 0, lastCount := 0
DllCall("QueryPerformanceFrequency", "Int64*", &freq)
DllCall("QueryPerformanceCounter", "Int64*", &lastCount)

Hotkey(CFG.ExitKey, (*) => ExitApp())
OnExit(OnScriptExit)
SetTimer(Update, CFG.PollMs)
SetTimer(Turn, CFG.MouseMs)
SetTimer(Heartbeat, CFG.HeartbeatMs)
A_IconTip := "PathFinder (idle)"

; Tells the addon this script is running. Only while WoW has focus, so the key goes to the game.
Heartbeat() {
    if WowFocused()
        Send(CFG.HeartbeatKey)
}

OnScriptExit(*) {
    ReleaseAll()
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}

WowFocused() {
    try return RegExMatch(WinGetProcessName("A"), CFG.WowExeRegex) > 0
    return false
}

; 0-3 for a channel near one of the four levels, -1 for anything else.
Level(v) {
    lvl := Round(v / 85)
    return Abs(v - lvl * 85) <= 30 ? lvl : -1
}

; The dot's reading as "g r b" levels, or "" if it isn't one of ours.
ReadDot() {
    CoordMode("Pixel", "Client")
    half := CFG.DotSize // 2
    try color := Integer(PixelGetColor(half, CFG.DotSize + half))
    catch
        return ""
    r := Level((color >> 16) & 0xFF), g := Level((color >> 8) & 0xFF), b := Level(color & 0xFF)
    if r < 0 || g < 0 || b < 0 || (r > 0 && b > 0)
        return ""
    return g " " r " " b
}

Update() {
    global last
    reading := WowFocused() ? ReadDot() : ""
    if reading = "" {
        last := ""
        Apply("0 0 0")
        return
    }
    if reading = last
        Apply(reading)
    last := reading
}

; Carries out a "g r b" reading: keys and mouse button now, turn speed via Turn().
Apply(reading) {
    global current, holdingKey, holdingMouse, want
    if reading = current
        return
    parts := StrSplit(reading, " ")
    g := Integer(parts[1]), r := Integer(parts[2]), b := Integer(parts[3])
    jumpNow := g = 2 && !want.jump
    want := { forward: g >= 2, turn: b - r, jump: g = 2, steer: g >= 1 }   ; turn > 0 = right

    if want.forward && !holdingKey {
        holdingKey := true
        Send("{" CFG.Keys.forward " down}")
    } else if !want.forward && holdingKey {
        holdingKey := false
        Send("{" CFG.Keys.forward " up}")
    }

    if want.steer && !holdingMouse {
        holdingMouse := true
        Send("{RButton down}")
    } else if !want.steer && holdingMouse {
        holdingMouse := false
        Send("{RButton up}")
    }

    if jumpNow
        Send("{" CFG.Keys.jump "}")
    A_IconTip := want.steer ? "PathFinder (steering)" : "PathFinder (idle)"
    current := reading
}

; Glides the turn speed toward what the dot asks, then moves the mouse by exactly speed * time.
Turn() {
    global speed, carry, lastCount
    now := 0
    DllCall("QueryPerformanceCounter", "Int64*", &now)
    dt := (now - lastCount) / freq
    lastCount := now
    if dt > 0.1
        dt := 0.1                   ; after a stall, don't jump
    if !holdingMouse {
        speed := 0.0, carry := 0.0
        return
    }
    target := want.turn / 3 * CFG.TurnSpeed
    speed += (target - speed) * (1 - Exp(-dt / CFG.TurnEase))
    carry += speed * dt
    px := Integer(carry)            ; whole pixels, toward zero
    if px != 0 {
        carry -= px
        MouseMove(px, 0, 0, "R")
    }
}

ReleaseAll() {
    global holdingKey, holdingMouse, current, want
    if holdingKey {
        holdingKey := false
        Send("{" CFG.Keys.forward " up}")
    }
    if holdingMouse {
        holdingMouse := false
        Send("{RButton up}")
    }
    want := { forward: false, turn: 0, jump: false, steer: false }
    current := ""
}
