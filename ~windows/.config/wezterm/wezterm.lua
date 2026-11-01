-- WezTerm on Windows, loaded through WEZTERM_CONFIG_FILE (set by ~windows/setup.ps1).
-- Minimal window: no title bar, tab bar at the bottom only when there are 2+ tabs.
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.default_prog = { os.getenv 'LOCALAPPDATA' .. '\\Programs\\Git\\bin\\bash.exe', '-i', '-l' }

config.font = wezterm.font 'JetBrainsMono Nerd Font Mono'
config.font_size = 11

-- Follows the Windows dark/light mode (Alt+Shift+D)
local function scheme(appearance)
  return appearance:find 'Dark' and 'OneHalfDark' or 'OneHalfLight'
end
config.color_scheme = scheme(wezterm.gui and wezterm.gui.get_appearance() or 'Dark')

config.window_decorations = 'RESIZE'
config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

config.default_cursor_style = 'SteadyBar'
config.audible_bell = 'Disabled'
config.window_close_confirmation = 'NeverPrompt'
config.check_for_updates = false

return config
