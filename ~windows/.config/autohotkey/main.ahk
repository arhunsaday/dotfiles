; Keyboard tweaks that need no admin rights (AutoHotkey v2).
; Started at logon by a shortcut that ~windows/setup.ps1 puts in the Startup folder.
; Window management keys live in ../glazewm/config.yaml, not here.

#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook
SetCapsLockState "AlwaysOff"

Scripts := A_ScriptDir "\..\..\scripts"
CapsHeld := false

; ==============================================================================
; CapsLock: Ctrl when held, Escape when tapped (Karabiner on the mac)
; ==============================================================================

*CapsLock::
{
    global CapsHeld := true
    Send "{Blind}{LCtrl down}"
    KeyWait "CapsLock"
    Send "{Blind}{LCtrl up}"
    CapsHeld := false
    if (A_PriorKey = "CapsLock" && A_TimeSinceThisHotkey < 250)
        Send "{Esc}"
}

; CapsLock+Space opens Keypirinha (its own hotkey is Alt+Space). Only the
; CapsLock Ctrl: the real Ctrl+Space stays free for editor completion.
; Ctrl is released explicitly: Send "!{Space}" alone left it down, giving Ctrl+Alt+Space.
#HotIf CapsHeld
*Space::Send "{LCtrl up}{LAlt down}{Space}{LAlt up}"
#HotIf

; ==============================================================================
; Right Alt + letter: focus the app, or launch it (Karabiner right_option rules)
; The * lets these fire through AltGr (LCtrl+RAlt) on the AZERTY layout too.
; ==============================================================================

*>!a::FocusOrRun("ahk_exe firefox.exe", "firefox.exe")
*>!t::FocusOrRun("ahk_exe WindowsTerminal.exe", "wt.exe")
*>!c::FocusOrRun("ahk_exe Code.exe", "code")
*>!f::FocusOrRun("ahk_class CabinetWClass", "explorer.exe")

FocusOrRun(winTitle, target) {
    if WinExist(winTitle)
        WinActivate
    else
        Run target
}

; ==============================================================================
; Theme / wallpaper (the Settings pages for both are blocked by policy)
; ==============================================================================

!+d::RunScript("switch-theme.ps1")

RunScript(name, args := "") {
    Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' Scripts "\" name '" ' args, , "Hide"
}

; ==============================================================================
; Explorer: Ctrl+Shift+. toggles hidden files, like Cmd+Shift+. in Finder
; ==============================================================================

#HotIf WinActive("ahk_class CabinetWClass")
^+.::
{
    key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    RegWrite RegRead(key, "Hidden") = 1 ? 2 : 1, "REG_DWORD", key, "Hidden"
    Send "{F5}"
}
#HotIf
