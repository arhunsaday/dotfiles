# Windows counterpart of ../dotfiles.sh, for a machine without admin rights.
#
# Symlinks need admin (or Developer Mode) on Windows, so stow is out. Instead
# every tool is pointed at this repo: an environment variable when the tool
# reads one, a one-line include stub when the config format has includes, and
# a plain copy for the few apps that rewrite their own settings file.
#
#   powershell -ExecutionPolicy Bypass -File setup.ps1 [-Environment work|perso] [-SkipApps] [-Force]
#
#   -SkipApps   only wire the configs, install nothing
#   -Force      overwrite the copied configs (Windows Terminal, Flow Launcher)
[CmdletBinding()]
param(
    [ValidateSet('work', 'perso')][string]$Environment,
    [switch]$SkipApps,
    [switch]$Force
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Win     = $PSScriptRoot
$Repo    = Split-Path $Win -Parent
$RepoFwd = $Repo.Replace('\', '/')
$EnvFile = "$HOME\.dotfiles-env"
$Backup  = "$HOME\.dotfiles-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
$Scoop   = "$HOME\scoop"
$Failed  = 0

# ---------------------------------------------------------------- output ----

function Section($title) {
    Write-Host "`n  $title"
}

function Report($color, $icon, $name, $detail) {
    Write-Host '    ' -NoNewline
    Write-Host $icon -ForegroundColor $color -NoNewline
    Write-Host (' {0,-22} ' -f $name) -NoNewline
    Write-Host $detail -ForegroundColor DarkGray
}

function Tilde($path) {
    $path.Replace($HOME, '~')
}

# ----------------------------------------------------------------- files ----

# Move a file we are about to replace into the backup dir, keeping its path
function Backup-File($path) {
    $dest = Join-Path $Backup ($path.Substring($HOME.Length).TrimStart('\'))
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Move-Item -LiteralPath $path $dest -Force
}

# Write a small file that includes the real one from the repo
function Write-Stub($path, $content) {
    $name = Tilde $path
    if (Test-Path -LiteralPath $path) {
        if ((Get-Content -LiteralPath $path -Raw) -eq $content) {
            Report DarkGray '·' $name 'up to date'
            return
        }
        Backup-File $path
        $note = ' · old one backed up'
    }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $content)
    Report Green '✔' $name "includes the repo$note"
}

# Copy a config the app rewrites itself (so an include or env var would not stick)
function Copy-Config($source, $dest) {
    $name = Tilde $dest
    if (-not (Test-Path (Split-Path $dest))) {
        Report DarkGray '·' $name 'app not installed, skipped'
        return
    }
    if (Test-Path -LiteralPath $dest) {
        if (-not $Force) {
            Report DarkGray '·' $name 'exists, kept (-Force to overwrite)'
            return
        }
        Backup-File $dest
    }
    Copy-Item -LiteralPath $source $dest
    Report Green '✔' $name "copied from $(Tilde $source)"
}

function Set-UserEnv($name, $value) {
    if ([Environment]::GetEnvironmentVariable($name, 'User') -eq $value) {
        Report DarkGray '·' $name 'up to date'
    } else {
        [Environment]::SetEnvironmentVariable($name, $value, 'User')
        Report Green '✔' $name (Tilde $value)
    }
    Set-Item "env:$name" $value
}

# ------------------------------------------------------------------ apps ----

function Install-Apps {
    Section 'apps'

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        # in a child process: the installer may call exit
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'Invoke-RestMethod https://get.scoop.sh | Invoke-Expression'
        $env:Path = "$Scoop\shims;$env:Path"
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Report Red '✖' 'scoop' 'install failed, see the output above'
            $script:Failed++
            return
        }
        Report Green '✔' 'scoop' "installed in $(Tilde $Scoop)"
    }

    $apps = Get-Content "$Win\scoop-apps.txt" |
        ForEach-Object { ($_ -replace '#.*').Trim() } |
        Where-Object { $_ }

    $buckets = @(scoop bucket list | ForEach-Object Name)
    foreach ($bucket in $apps | ForEach-Object { $_.Split('/')[0] } | Select-Object -Unique) {
        if ($bucket -notin $buckets) {
            scoop bucket add $bucket | Out-Null
            Report Green '✔' "bucket $bucket" 'added'
        }
    }

    $installed = @(scoop list 6>$null | ForEach-Object Name)
    $missing = @($apps | Where-Object { $_.Split('/')[1] -notin $installed })
    if ($missing.Count -eq 0) {
        Report DarkGray '·' 'scoop apps' "$($apps.Count) up to date"
    } else {
        scoop install @missing
        $still = @($missing | Where-Object { $_.Split('/')[1] -notin @(scoop list 6>$null | ForEach-Object Name) })
        if ($still.Count -gt 0) {
            Report Red '✖' 'scoop apps' "failed: $($still -join ', ')"
            $script:Failed++
        } else {
            Report Green '✔' 'scoop apps' "$($missing.Count) installed"
        }
    }

    if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path "$HOME\.local\bin\claude.exe")) {
        Report DarkGray '·' 'claude' 'already installed'
    } else {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression'
        if (Test-Path "$HOME\.local\bin\claude.exe") {
            Report Green '✔' 'claude' 'installed in ~\.local\bin'
        } elseif (Test-Path "$HOME\.vscode\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe") {
            # the proxy can block .exe downloads (an HTML page comes back instead)
            Report Yellow '!' 'claude' 'download failed, bash uses the VS Code extension binary'
        } else {
            Report Red '✖' 'claude' 'download failed, install the VS Code extension or ask IT'
            $script:Failed++
        }
    }
}

# ---------------------------------------------------------------- config ----

function Install-Config {
    Section 'environment variables'

    Set-UserEnv DOTFILES_DIR        $Repo
    Set-UserEnv GLAZEWM_CONFIG_PATH "$Win\.config\glazewm\config.yaml"
    Set-UserEnv YASB_CONFIG_HOME    "$Win\.config\yasb"
    Set-UserEnv WEZTERM_CONFIG_FILE "$Win\.config\wezterm\wezterm.lua"
    Set-UserEnv RIO_CONFIG_HOME     "$Win\.config\rio"
    Set-UserEnv STARSHIP_CONFIG     "$Repo\starship\.config\starship.toml"
    Set-UserEnv LG_CONFIG_FILE      "$Repo\lazygit\.config\lazygit\config.yml"

    # Node ships its own CA list, so it rejects any proxy that re-signs TLS.
    # Hand it every root Windows trusts instead (the rest of the tools use the
    # Windows store already: git through schannel, uv through system-certs).
    $pem = "$HOME\.config\certs\windows-roots.pem"
    New-Item -ItemType Directory -Force (Split-Path $pem) | Out-Null
    Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root |
        Sort-Object Thumbprint -Unique |
        ForEach-Object {
            '-----BEGIN CERTIFICATE-----'
            [Convert]::ToBase64String($_.RawData) -split '(.{64})' | Where-Object { $_ }
            '-----END CERTIFICATE-----'
        } |
        Set-Content $pem -Encoding Ascii
    Set-UserEnv NODE_EXTRA_CA_CERTS $pem

    Section 'language'

    # English first with the US keyboard, French kept second (Win+Space switches).
    # The display language stays French: only that pack is installed, and a
    # policy pins it anyway.
    $langs = Get-WinUserLanguageList
    if ($langs[0].LanguageTag -eq 'en-US' -and
        (Get-WinDefaultInputMethodOverride).InputMethodTip -eq '0409:00000409') {
        Report DarkGray '·' 'en-US keyboard' 'up to date'
    } else {
        $list = New-WinUserLanguageList en-US
        $langs | Where-Object LanguageTag -ne 'en-US' | ForEach-Object { $list.Add($_) }
        Set-WinUserLanguageList $list -Force
        Set-WinDefaultInputMethodOverride -InputTip '0409:00000409'
        Report Green '✔' 'en-US keyboard' 'default, French second'
    }

    Section 'shell, git, vim'

    Write-Stub "$HOME\.bashrc"       ". `"$RepoFwd/bash/.bashrc`"`n"
    Write-Stub "$HOME\.bash_profile" ". `"$RepoFwd/bash/.bash_profile`"`n"
    Write-Stub "$HOME\.config\git\git-prompt.sh" ". `"$RepoFwd/~windows/.config/git/git-prompt.sh`"`n"
    Write-Stub "$HOME\.vimrc"        "source $RepoFwd/vim/.vimrc`n"
    if (-not (Test-Path "$env:LOCALAPPDATA\nvim\init.lua")) {
        Write-Stub "$env:LOCALAPPDATA\nvim\init.vim" "source ~/.vimrc`n"
    }

    # ~/.gitignore_global is read through core.excludesfile, which has no include.
    # Vim rather than the mac's nvim: Git for Windows ships it.
    Write-Stub "$HOME\.gitconfig" @"
[include]
	path = $RepoFwd/git/.gitconfig
[core]
	excludesfile = $RepoFwd/git/.gitignore_global
	editor = vim

"@
    Write-Stub "$HOME\.gitconfig-local" "[include]`n`tpath = $RepoFwd/~$Environment/.gitconfig-local`n"
    Write-Stub "$HOME\.gitconfig-work"  "[include]`n`tpath = $RepoFwd/git/.gitconfig-work`n"
    Write-Stub "$HOME\.gitconfig-perso" "[include]`n`tpath = $RepoFwd/git/.gitconfig-perso`n"

    Section 'apps settings'

    Copy-Config "$Win\.config\windows-terminal.json" "$Scoop\persist\windows-terminal\settings\settings.json"
    Copy-Config "$Win\.config\flow-launcher.json"    "$Scoop\persist\flow-launcher\UserData\Settings\Settings.json"
    # Keypirinha only creates its profile dir on first run
    if (Test-Path "$Scoop\apps\keypirinha") {
        New-Item -ItemType Directory -Force "$Scoop\persist\keypirinha\portable\Profile\User" | Out-Null
    }
    Copy-Config "$Win\.config\keypirinha\keypirinha.ini" "$Scoop\persist\keypirinha\portable\Profile\User\Keypirinha.ini"
    Copy-Config "$Win\.config\keypirinha\apps.ini"       "$Scoop\persist\keypirinha\portable\Profile\User\Apps.ini"
}

# --------------------------------------------------------------- startup ----

# Find an exe inside a Scoop app, optionally preferring a path matching $prefer
function Find-AppExe($app, $exe, $prefer) {
    $dir = "$Scoop\apps\$app\current"
    if (-not (Test-Path $dir)) { return $null }
    Get-ChildItem $dir -Recurse -Filter $exe -ErrorAction SilentlyContinue |
        Sort-Object { if ($prefer -and $_.FullName -match $prefer) { 0 } else { 1 } }, { $_.FullName.Length } |
        Select-Object -First 1 -ExpandProperty FullName
}

function Install-Startup {
    Section 'start at logon'

    $startup = [Environment]::GetFolderPath('Startup')
    $shell = New-Object -ComObject WScript.Shell

    $entries = @(
        @{ Name = 'GlazeWM';       Exe = (Find-AppExe glazewm 'glazewm.exe' '\\current\\[^\\]*$');
           Args = "start --config=`"$Win\.config\glazewm\config.yaml`"" }
        @{ Name = 'YASB';          Exe = (Find-AppExe yasb 'yasb.exe' '\\current\\[^\\]*$'); Args = '' }
        @{ Name = 'AutoHotkey';    Exe = (Find-AppExe autohotkey 'AutoHotkey64.exe' '\\v2\\');
           Args = "`"$Win\.config\autohotkey\main.ahk`"" }
        @{ Name = 'WinCompose';    Exe = (Find-AppExe wincompose 'wincompose.exe'); Args = '' }
        @{ Name = 'Keypirinha';    Exe = (Find-AppExe keypirinha 'keypirinha.exe' '\\current\\[^\\]*$'); Args = '' }
    )

    foreach ($entry in $entries) {
        if (-not $entry.Exe) {
            Report DarkGray '·' $entry.Name 'not installed, skipped'
            continue
        }
        $link = $shell.CreateShortcut((Join-Path $startup "$($entry.Name).lnk"))
        $link.TargetPath = $entry.Exe
        $link.Arguments = $entry.Args
        $link.WorkingDirectory = Split-Path $entry.Exe
        $link.Save()

        $running = Get-Process ([IO.Path]::GetFileNameWithoutExtension($entry.Exe)) -ErrorAction SilentlyContinue
        if ($running) {
            Report Green '✔' $entry.Name 'shortcut in Startup · already running'
        } else {
            if ($entry.Args) {
                Start-Process $entry.Exe -ArgumentList $entry.Args
            } else {
                Start-Process $entry.Exe
            }
            Report Green '✔' $entry.Name 'shortcut in Startup · started'
        }
    }
}

# ------------------------------------------------------------------ main ----

if (-not $Environment -and (Test-Path $EnvFile)) {
    $Environment = (Get-Content $EnvFile -TotalCount 1).Trim()
}
if ($Environment -notin 'work', 'perso') {
    Write-Host "`n  ✖ no environment selected — pass -Environment work or perso the first time`n" -ForegroundColor Red
    exit 1
}

Write-Host "`n  dotfiles  $(Tilde $Repo) → ~" -NoNewline
Write-Host "  (windows · $Environment)" -ForegroundColor DarkGray

if (-not $SkipApps) { Install-Apps }
Install-Config
Install-Startup

[IO.File]::WriteAllText($EnvFile, "$Environment`n")

Write-Host "`n  $('─' * 44)" -ForegroundColor DarkGray
if ($Failed -gt 0) {
    Report Red '✖' "$Failed failed" 'see above'
} else {
    Report Green '✔' 'install done' 'open a new terminal to pick up the environment'
}
if (Test-Path $Backup) {
    Report Yellow '!' 'replaced files' "saved to $(Tilde $Backup)"
}
Write-Host ''
exit [int]($Failed -gt 0)
