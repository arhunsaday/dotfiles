# Set the desktop wallpaper. The Settings page is disabled by policy
# (NoChangingWallPaper), but that only hides the UI: the API still works.
#
#   set-wallpaper.ps1 C:\path\to\image.jpg
param([Parameter(Mandatory)][string]$Path)

$image = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path

# Fill the screen, no tiling
$desktop = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'
Set-ItemProperty $desktop -Name TileWallpaper  -Value '0'

Add-Type -Namespace Dotfiles -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
'@

# SPI_SETDESKWALLPAPER, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
if (-not [Dotfiles.Wallpaper]::SystemParametersInfo(0x14, 0, $image, 3)) {
    throw "SystemParametersInfo failed (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
}
