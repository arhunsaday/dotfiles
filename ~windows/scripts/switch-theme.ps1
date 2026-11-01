# Switch the system + apps theme. The Settings page is disabled by policy
# (NoDispAppearancePage), but the per-user registry values are still writable.
#
#   switch-theme.ps1            toggle
#   switch-theme.ps1 dark|light
#
# If <Pictures>\Wallpapers holds a dark.* / light.* image, it becomes the
# wallpaper for that theme.
param([ValidateSet('toggle', 'dark', 'light')][string]$Mode = 'toggle')

$reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$light = switch ($Mode) {
    'dark'  { 0 }
    'light' { 1 }
    default { 1 - (Get-ItemPropertyValue $reg -Name AppsUseLightTheme) }
}

Set-ItemProperty $reg -Name AppsUseLightTheme    -Value $light
Set-ItemProperty $reg -Name SystemUsesLightTheme -Value $light

# Broadcast the change so all apps update immediately
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinMsg {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
$result = [UIntPtr]::Zero
[WinMsg]::SendMessageTimeout(
    [IntPtr]0xFFFF, 0x001A, [UIntPtr]::Zero, "ImmersiveColorSet",
    0x0002, 5000, [ref]$result
) | Out-Null

$name = if ($light) { 'light' } else { 'dark' }
$wallpapers = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Wallpapers'
$image = Get-ChildItem $wallpapers -File -Filter "$name.*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($image) {
    & "$PSScriptRoot\set-wallpaper.ps1" $image.FullName
}
