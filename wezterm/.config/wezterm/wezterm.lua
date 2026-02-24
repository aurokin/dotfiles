local wezterm = require("wezterm")

local config = wezterm.config_builder and wezterm.config_builder() or {}

config.font = wezterm.font({
  family = "RobotoMono Nerd Font",
  weight = "Regular",
})
config.font_size = 15.0

config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}
config.window_background_opacity = 0.9
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.show_tab_index_in_tab_bar = false
config.tab_max_width = 24

-- Tokyo Night colors aligned with this repo's Alacritty/Ghostty palette.
config.colors = {
  foreground = "#c0caf5",
  background = "#101217",

  cursor_bg = "#c0caf5",
  cursor_fg = "#101217",
  cursor_border = "#c0caf5",

  ansi = {
    "#15161e",
    "#f7768e",
    "#9ece6a",
    "#e0af68",
    "#7aa2f7",
    "#bb9af7",
    "#7dcfff",
    "#a9b1d6",
  },
  brights = {
    "#414868",
    "#f7768e",
    "#9ece6a",
    "#e0af68",
    "#7aa2f7",
    "#bb9af7",
    "#7dcfff",
    "#c0caf5",
  },
  indexed = {
    [16] = "#ff9e64",
    [17] = "#db4b4b",
  },
  tab_bar = {
    background = "#101217",
    active_tab = {
      bg_color = "#1f2335",
      fg_color = "#c0caf5",
      intensity = "Bold",
      underline = "None",
      italic = false,
      strikethrough = false,
    },
    inactive_tab = {
      bg_color = "#101217",
      fg_color = "#565f89",
      intensity = "Normal",
      underline = "None",
      italic = false,
      strikethrough = false,
    },
    inactive_tab_hover = {
      bg_color = "#15161e",
      fg_color = "#a9b1d6",
      intensity = "Normal",
      underline = "None",
      italic = false,
      strikethrough = false,
    },
    new_tab = {
      bg_color = "#101217",
      fg_color = "#565f89",
    },
    new_tab_hover = {
      bg_color = "#15161e",
      fg_color = "#a9b1d6",
    },
  },
}

return config
