-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_scheme = 'Vibrant Ink'

config.enable_tab_bar = false

config.font = wezterm.font('GoMono Nerd Font Mono', {})
config.font_size = 14
config.line_height = 0.9

config.window_background_opacity = 0.7

config.default_prog = { '/opt/homebrew/bin/tmux', 'new', '-As', 'shell', '--', '/bin/zsh' }

config.audible_bell = 'Disabled'

-- and finally, return the configuration to wezterm
return config
