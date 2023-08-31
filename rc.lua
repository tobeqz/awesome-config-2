-- awesome_mode: api-level=4:screen=on
-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

-- Standard awesome library
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
-- Widget and layout library
local wibox = require("wibox")
-- Theme handling library
local beautiful = require("beautiful")
-- Notification library
local naughty = require("naughty")
-- Declarative object management
local ruled = require("ruled")
local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup")
local json = require("cjson");
-- Enable hotkeys help widget for VIM and other apps
-- when client with a matching name is opened:
require("awful.hotkeys_popup.keys")

local swipe_event_path = "/home/main/.config/awesome/events/swipe_gesture"

gears.timer.start_new(0.05, function()
  -- Get file contents
  local swipe_event_file = io.open(swipe_event_path, "r+")
  local content = swipe_event_file:read("*all")
  swipe_event_file:close()

  --naughty.notification { message = content }

  if content ~= "" then
    -- Switch tag
    if content == "left\n" then
      awful.tag.viewprev(awful.screen.focused())
    elseif content == "right\n" then
      awful.tag.viewnext(awful.screen.focused())
    end
    -- Delete contents
    io.open(swipe_event_path, "w"):close()
  end

  return true
end)

--j{{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
naughty.connect_signal("request::display_error", function(message, startup)
  naughty.notification({
    urgency = "critical",
    title = "Oops, an error happened" .. (startup and " during startup!" or "!"),
    message = message,
  })
end)
-- }}}

-- {{{ Variable definitions
-- Themes define colours, icons, font and wallpapers.
beautiful.init("/home/main/.config/awesome/theme.lua")
local theme = beautiful.get()

-- This is used later as the default terminal and editor to run.
terminal = "alacritty"
editor = os.getenv("EDITOR") or "nano"
editor_cmd = terminal .. " -e " .. editor

-- Default modkey.
-- Usually, Mod4 is the key with a logo between Control and Alt.
-- If you do not like this or do not have such a key,
-- I suggest you to remap Mod4 to another key using xmodmap or other tools.
-- However, you can use another modifier like Mod1, but it may interact with others.
modkey = "Mod4"
-- }}}

-- {{{ Menu

mylauncher = awful.widget.launcher({ image = beautiful.awesome_icon, menu = mymainmenu })
-- Menubar configuration
menubar.utils.terminal = terminal -- Set the terminal for applications that require it
-- }}}

-- {{{ Tag layout
-- Table of layouts to cover with awful.layout.inc, order matters.
tag.connect_signal("request::default_layouts", function()
  awful.layout.append_default_layouts({
    awful.layout.suit.tile,
    awful.layout.suit.fair,
    awful.layout.suit.spiral,
    awful.layout.suit.spiral.dwindle,
  })
end)
-- }}}

-- {{{ Wallpaper
screen.connect_signal("request::wallpaper", function(s)
  awful.wallpaper({
    screen = s,
    bg = "#232634",
    --widget = {
    --    {
    --        image     = beautiful.wallpaper,
    --        upscale   = true,
    --        downscale = true,
    --        resize    = true,
    --        widget    = wibox.widget.imagebox,
    --    },
    --    valign = "center",
    --    halign = "center",
    --    tiled  = false,
    --    widget = wibox.container.tile,
    --}
  })
end)
-- }}}

-- {{{ Wibar

-- Keyboard map indicator and switcher
-- mykeyboardlayout = awful.widget.keyboardlayout()

-- Create a textclock widget
mytextclock = wibox.widget.textclock(" <b>%H:%M</b>")

function parse_battery_info(out)
  --return {
  --    percentage = 10,
  --    charge_state = "Discharging",
  --    time_estimate = "3"
  --}

  local inputs = {}

  for v in string.gmatch(out, "%S+") do
    table.insert(inputs, v)
  end

  return {
    percentage = tonumber(inputs[1]),
    charge_state = inputs[2],
    time_estimate = inputs[3],
  }
end

function get_percentage_icon(percentage)
  local icons = {
    "󰁺",
    "󰁻",
    "󰁼",
    "󰁽",
    "󰁾",
    "󰁿",
    "󰂀",
    "󰂁",
    "󰂂",
    "󰁹",
  }

  if percentage == 100 then
    return icons[10]
  end

  return icons[(math.floor(percentage / 10) + 1)]
  --return icons[1]
end

local battery_path = "/home/main/.config/awesome/rust_projects/get_battery_percent/target/release/get_battery_percent"
local battery_percent_watch = wibox.widget({
  layout = wibox.layout.fixed.horizontal,
})

gears.timer({
  timeout = 1,
  call_now = true,
  autostart = true,
  callback = function()
    awful.spawn.easy_async(battery_path, function(stdout)
      local status, err = pcall(function()
        local battery = parse_battery_info(stdout)

        local icon = "󰂄"
        if battery.percentage == nil then
          naughty.notification({message = "no percentage"})
          return
        end

        if battery.charge_state == "Charging" or battery.charge_state == "NotCharging" or battery.charge_state == "Full" then
        else
          icon = get_percentage_icon(battery.percentage)
        end

        battery_percent_watch.children = {
          {
            widget = wibox.widget.textbox,
            text = icon,
            font = theme.icon_font,
          },
          wibox.widget.textbox(" <b>" .. battery.percentage .. "%</b> (" .. battery.time_estimate .. "h)"),
        }
      end)

      if not status then
        naughty.notification({ message = err })
      end
    end)
  end,
})

local title_textbox = wibox.widget {
  widget = wibox.widget.textbox,
  text = "";
}

local music_progress = wibox.widget {
  widget = wibox.widget.progressbar,
  max_value = 1.0,
  value = 0.5,
  height = 10,
  forced_width = 75,
  background_color = theme.bg_focus,
  color = theme.bg_urgent,
  shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, 20)
  end
}

local mpris_control_path = "/home/main/.config/awesome/rust_projects/control-music/target/release/control-music"

local prev_button = wibox.widget {
  widget = wibox.widget.textbox,
  font = "monospace 25",
  text = "󰒮"
}

prev_button:connect_signal("button::press", function(s) 
  awful.spawn.easy_async(mpris_control_path .. " prev", function() end)
end)

local next_button = wibox.widget {
  widget = wibox.widget.textbox,
  font = "monospace 25",
  text = "󰒭"
}

next_button:connect_signal("button::press", function(s) 
  awful.spawn.easy_async(mpris_control_path .. " next", function() end)
end)

local play_pause_button = wibox.widget {
  widget = wibox.widget.textbox,
  font = "monospace 25",
  text = ""
}

play_pause_button:connect_signal("button::press", function(s)
  awful.spawn.easy_async(mpris_control_path .. " play-pause", function(stdout) end);
end)

local function trim(s)
   return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local mpris_widget = wibox.widget({
  widget = wibox.layout.fixed.horizontal,
  spacing = 10,
  {
    layout = wibox.layout.fixed.horizontal,
    spacing = 2.5,
    prev_button,
    play_pause_button,
    next_button
  },
  {
    layout = wibox.container.place,
    music_progress
  },
  {
    layout = wibox.container.scroll.horizontal,
    max_size = 150,
    speed = 50,
    title_textbox,
  }
})

gears.timer({
  timeout = 0.5,
  call_now = true,
  autostart = true,
  callback = function()
    awful.spawn.easy_async(mpris_control_path .. " get-length", function(stdout)
      local length = json.decode(stdout)
      awful.spawn.easy_async(mpris_control_path .. " get-position", function(stdout2)
        local position = json.decode(stdout2)

        music_progress.value = position / length;
      end)
    end)

    awful.spawn.easy_async(mpris_control_path .. " get-status", function(stdout)
      play_pause_button.text = trim(stdout) == "Playing" and "󰏤" or "";
    end)

    awful.spawn.easy_async(mpris_control_path .. " all-data", function(stdout)
      local metadata = json.decode(stdout);

      if metadata.title == json.null or metadata.artists == json.null then
        title_textbox.text = "";
        return
      else
      end

      local title = metadata.title;
      local artists = table.concat(metadata.artists, ", ");

      title_textbox.text = artists .. " - " .. title .. " | ";
    end)
  end
})

local volume_bar = wibox.widget {
  widget = wibox.widget.progressbar,
  max_value = 1.0,
  value = 0.5,
  height = 10,
  forced_width = 120,
  background_color = theme.bg_focus,
  color = theme.bg_urgent,
  shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, 20)
  end
}

volume_bar:connect_signal("button::press", function(self, lx)
  local alpha = lx / 120
  local percentage = alpha * 100
  awful.spawn.easy_async("pamixer --set-volume " .. tostring(math.floor(percentage)), function(stdout)
  end);
  --naughty.notification{message = tostring(lx)}
end)

-- amixer get Master | grep -Po "Front Left: Playback.*\[\K(.*)(?=%\])"
local volume_widget = wibox.widget {
  widget = wibox.layout.fixed.horizontal,
  {
    widget = wibox.widget.textbox,
    font = "monospace 25",
    text = "󰕾"
  },
  {
    widget = wibox.container.margin,
    left = 8,
    {
      widget = wibox.container.place,
      volume_bar,
    }
  },
}

-- amixer get Master | grep -Po "Front Left: Playback.*\\[\\K(.*)(?=%\\])"
gears.timer({
  timeout = 0.2,
  call_now = true,
  autostart = true,
  callback = function()
    awful.spawn.easy_async('pamixer --get-volume', function(stdout)
      local percentage = tonumber(trim(stdout))
      if percentage == nil then return end
      local alpha = percentage / 100
      volume_bar.value = alpha
    end)
  end
})


local brightness_bar = wibox.widget {
  widget = wibox.widget.progressbar,
  max_value = 1.0,
  value = 0.5,
  height = 10,
  forced_width = 120,
  background_color = theme.bg_focus,
  color = theme.bg_urgent,
  shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, 20)
  end
}

brightness_bar:connect_signal("button::press", function(self, lx)
  local alpha = lx / self.forced_width
  local percentage = alpha * 100
  awful.spawn.easy_async("xbacklight " .. tostring(math.floor(percentage)), function(stdout)
  end);
end)

-- amixer get Master | grep -Po "Front Left: Playback.*\[\K(.*)(?=%\])"
local brightness_widget = wibox.widget {
  widget = wibox.layout.fixed.horizontal,
  {
    widget = wibox.widget.textbox,
    font = "monospace 25",
    text = "󰃠"
  },
  {
    widget = wibox.container.margin,
    left = 8,
    {
      widget = wibox.container.place,
      brightness_bar,
    }
  },
}

-- amixer get Master | grep -Po "Front Left: Playback.*\\[\\K(.*)(?=%\\])"
gears.timer({
  timeout = 0.2,
  call_now = true,
  autostart = true,
  callback = function()
    awful.spawn.easy_async('xbacklight -get', function(stdout)
      local percentage = tonumber(trim(stdout))
      if percentage == nil then return end
      local alpha = percentage / 100
      brightness_bar.value = alpha
    end)
  end
})


--local battery_percent_watch = awful.widget.watch(battery_path, 3, function(widget, stdout)
--    local status, err = pcall(function()
--        local battery = parse_battery_info(widget, stdout)
--        local icon;
--        if battery.charge_state == "Charging" then
--            icon = "󰂄"
--        else
--            icon = get_percentage_icon(widget, battery.percentage)
--        end
--
--        widget:set_markup(icon .. " <b>" .. battery.percentage .. "</b>%")
--    end)
--
--    if not status then
--        widget:set_text(err)
--    end
--end);

screen.connect_signal("request::desktop_decoration", function(s)
  -- Each screen has its own tag table.
  awful.tag({ "1", "2", "3", "4", "5", "6", "7" }, s, awful.layout.layouts[1])

  -- Create a promptbox for each screen
  s.mypromptbox = awful.widget.prompt()

  s.tag_outline = wibox.widget({
    widget = wibox.widget.imagebox,
    image = "/home/main/dotfiles/awesome/images/Outline.svg",
    resize = true,
  })

  s.tag_center = wibox.widget({
    widget = wibox.container.margin,
    margins = 6,
    {
      widget = wibox.widget.imagebox,
      image = "/home/main/dotfiles/awesome/images/Center.svg",
      resize = true,
    },
  })

  s.tag_strikethrough = wibox.widget({
    widget = wibox.widget.imagebox,
    image = "/home/main/dotfiles/awesome/images/Strikethrough.svg",
    resize = true,
  })

  -- Create a taglist widget
  s.mytaglist = awful.widget.taglist({
    screen = s,
    filter = awful.widget.taglist.filter.all,
    style = {
      spacing = 4,
    },
    widget_template = {
      layout = wibox.layout.stack,
      update_callback = function(self, t)
        local children = { s.tag_outline }

        if t.selected then
          table.insert(children, s.tag_center)
        end

        if #t:clients() == 0 then
          table.insert(children, s.tag_strikethrough)
        end

        self.children = children
      end,
      create_callback = function(self, t)
        self.update_callback(self, t)
      end,
      s.tag_outline,
    },
    buttons = {
      awful.button({}, 1, function(t)
        t:view_only()
      end),
      awful.button({ modkey }, 1, function(t)
        if client.focus then
          client.focus:move_to_tag(t)
        end
      end),
      awful.button({}, 3, awful.tag.viewtoggle),
      awful.button({ modkey }, 3, function(t)
        if client.focus then
          client.focus:toggle_tag(t)
        end
      end),
      awful.button({}, 4, function(t)
        awful.tag.viewprev(t.screen)
      end),
      awful.button({}, 5, function(t)
        awful.tag.viewnext(t.screen)
      end),
    },
  })

  -- Create a tasklist widget
  s.mytasklist = awful.widget.tasklist({
    screen = s,
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = {
      awful.button({}, 1, function(c)
        c:activate({ context = "tasklist", action = "toggle_minimization" })
      end),
      awful.button({}, 3, function()
        awful.menu.client_list({ theme = { width = 250 } })
      end),
      awful.button({}, 4, function()
        awful.client.focus.byidx(-1)
      end),
      awful.button({}, 5, function()
        awful.client.focus.byidx(1)
      end),
    },
  })

  s.epicclock = wibox.widget({})

  function menu_container(w, dark)
    return {
      widget = wibox.container.background,
      bg = dark and theme.bg_normal or theme.outline_color,
      fg = dark and theme.fg_normal or theme.bg_normal,
      border_color = dark and theme.outline_color or nil,
      border_width = dark and theme.border_width or nil,
      border_strategy = "inner",
      --border_width = dark and 3 or theme.border_width,
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, height / 2)
      end,
      {
        widget = wibox.container.margin,
        top = theme.border_width,
        bottom = theme.border_width,
        top = 4,
        bottom = 4,
        left = 15,
        right = 15,
        w,
      },
    }
  end

  -- Create the wibox
  s.mywibar = awful.wibar({
    bg = gears.color.transparent,
    --bg = "#2E3440",
    position = "top",
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 8)
    end,
    height = 35,
    margins = {
      top = theme.useless_gap * 2,
      bottom = 0,
      left = theme.useless_gap * 2,
      right = theme.useless_gap * 2,
    },
    screen = s,
    widget = {
      layout = wibox.layout.ratio.horizontal,
      -- Left section of menu
      {
        widget = wibox.layout.fixed.horizontal,
        menu_container({
          widget = wibox.container.margin,
          top = 2.5,
          bottom = 2.5,
          s.mytaglist,
        }),
        {
          widget = wibox.container.margin,
          left = 10,
          menu_container(mpris_widget)
        }
      },
      -- Middle section of menu
      {
        widget = wibox.container.place,
        valign = center,
        halign = center,
        {
          layout = wibox.layout.fixed.horizontal,
          spacing = 10,
          menu_container({
            layout = wibox.layout.fixed.horizontal,
            {
              widget = wibox.widget.textbox,
              font = theme.icon_font,
              text = "",
            },
            mytextclock,
          }),
          menu_container(battery_percent_watch),
        },
      },
      {
        layout = wibox.layout.align.horizontal,
        wibox.widget({}),
        wibox.widget({}),
        {
        -- Right section of menu
          layout = wibox.layout.fixed.horizontal,
          spacing = 10,
          menu_container(brightness_widget),
          menu_container(volume_widget),
          menu_container({
            widget = wibox.layout.fixed.horizontal,
            {
              widget = wibox.widget.textbox,
              font = theme.icon_font,
              text = "󰃭",
            },
            wibox.widget.textclock(" %a %b %d"),
          }),
          menu_container(wibox.widget.systray(), true),
        },
      },
    },
  })

  s.mywibar.widget:adjust_widget_ratio(1, 1, (1 / 3), 1)
  s.mywibar.widget:adjust_widget_ratio(2, 1, (1 / 3), 1)
  s.mywibar.widget:adjust_widget_ratio(3, 1, (1 / 3), 1)
end)

-- }}}

-- }}}

-- {{{ Key bindings

-- General Awesome keys
awful.keyboard.append_global_keybindings({
  awful.key({ modkey }, "s", hotkeys_popup.show_help, { description = "show help", group = "awesome" }),
  awful.key({ modkey }, "w", function()
    mymainmenu:show()
  end, { description = "show main menu", group = "awesome" }),
  awful.key({ modkey, "Control" }, "r", awesome.restart, { description = "reload awesome", group = "awesome" }),
  awful.key({ modkey, "Shift" }, "q", awesome.quit, { description = "quit awesome", group = "awesome" }),
  awful.key({ modkey }, "x", function()
    awful.prompt.run({
      prompt = "Run Lua code: ",
      textbox = awful.screen.focused().mypromptbox.widget,
      exe_callback = awful.util.eval,
      history_path = awful.util.get_cache_dir() .. "/history_eval",
    })
  end, { description = "lua execute prompt", group = "awesome" }),
  awful.key({ modkey, "Shift" }, "Return", function()
    awful.spawn(terminal)
  end, { description = "open a terminal", group = "launcher" }),
  awful.key({ modkey }, "r", function()
    awful.screen.focused().mypromptbox:run()
  end, { description = "run prompt", group = "launcher" }),
  awful.key({ modkey }, "p", function()
    awesome.spawn("rofi -show drun")
  end, { description = "show the menubar", group = "launcher" }),
  awful.key({}, "#123", function() awful.spawn("amixer set Master 5%+") end),
  awful.key({}, "#122", function() awful.spawn("amixer set Master 5%-") end),
  awful.key({}, "#232", function() awful.spawn("xbacklight -5") end),
  awful.key({}, "#233", function() awful.spawn("xbacklight +5") end),
})

-- Tags related keybindings
awful.keyboard.append_global_keybindings({
  awful.key({ modkey }, "Left", awful.tag.viewprev, { description = "view previous", group = "tag" }),
  awful.key({ modkey }, "Right", awful.tag.viewnext, { description = "view next", group = "tag" }),
  awful.key({ modkey }, "Escape", awful.tag.history.restore, { description = "go back", group = "tag" }),
})

-- Focus related keybindings
awful.keyboard.append_global_keybindings({
  awful.key({ modkey }, "j", function()
    awful.client.focus.byidx(-1)
  end, { description = "focus previous by index", group = "client" }),
  awful.key({ modkey }, "k", function()
    awful.client.focus.byidx(1)
  end, { description = "focus next by index", group = "client" }),
  awful.key({ modkey }, "Tab", function()
    awful.client.focus.history.previous()
    if client.focus then
      client.focus:raise()
    end
  end, { description = "go back", group = "client" }),
  awful.key({ modkey }, ",", function()
    awful.screen.focus_relative(1)
  end, { description = "focus the next screen", group = "screen" }),
  awful.key({ modkey }, ".", function()
    awful.screen.focus_relative(-1)
  end, { description = "focus the previous screen", group = "screen" }),
  --awful.key({ modkey, "Control" }, "n",
  --          function ()
  --              local c = awful.client.restore()
  --              -- Focus restored client
  --              if c then
  --                c:activate { raise = true, context = "key.unminimize" }
  --              end
  --          end,
  --          {description = "restore minimized", group = "client"}),
})

-- Layout related keybindings
awful.keyboard.append_global_keybindings({
  awful.key({ modkey, "Shift" }, "j", function()
    awful.client.swap.byidx(1)
  end, { description = "swap with next client by index", group = "client" }),
  awful.key({ modkey, "Shift" }, "k", function()
    awful.client.swap.byidx(-1)
  end, { description = "swap with previous client by index", group = "client" }),
  awful.key({ modkey }, "u", awful.client.urgent.jumpto, { description = "jump to urgent client", group = "client" }),
  awful.key({ modkey }, "l", function()
    awful.tag.incmwfact(0.05)
  end, { description = "increase master width factor", group = "layout" }),
  awful.key({ modkey }, "h", function()
    awful.tag.incmwfact(-0.05)
  end, { description = "decrease master width factor", group = "layout" }),
  awful.key({ modkey, "Shift" }, "h", function()
    awful.tag.incnmaster(1, nil, true)
  end, { description = "increase the number of master clients", group = "layout" }),
  awful.key({ modkey, "Shift" }, "l", function()
    awful.tag.incnmaster(-1, nil, true)
  end, { description = "decrease the number of master clients", group = "layout" }),
  awful.key({ modkey, "Control" }, "h", function()
    awful.tag.incncol(1, nil, true)
  end, { description = "increase the number of columns", group = "layout" }),
  awful.key({ modkey, "Control" }, "l", function()
    awful.tag.incncol(-1, nil, true)
  end, { description = "decrease the number of columns", group = "layout" }),
  awful.key({ modkey }, "space", function()
    awful.layout.inc(1)
  end, { description = "select next", group = "layout" }),
  awful.key({ modkey, "Shift" }, "space", function()
    awful.layout.inc(-1)
  end, { description = "select previous", group = "layout" }),
})

awful.keyboard.append_global_keybindings({
  awful.key({
    modifiers = { modkey },
    keygroup = "numrow",
    description = "only view tag",
    group = "tag",
    on_press = function(index)
      local screen = awful.screen.focused()
      local tag = screen.tags[index]
      if tag then
        tag:view_only()
      end
    end,
  }),
  awful.key({
    modifiers = { modkey, "Control" },
    keygroup = "numrow",
    description = "toggle tag",
    group = "tag",
    on_press = function(index)
      local screen = awful.screen.focused()
      local tag = screen.tags[index]
      if tag then
        awful.tag.viewtoggle(tag)
      end
    end,
  }),
  awful.key({
    modifiers = { modkey, "Shift" },
    keygroup = "numrow",
    description = "move focused client to tag",
    group = "tag",
    on_press = function(index)
      if client.focus then
        local tag = client.focus.screen.tags[index]
        if tag then
          client.focus:move_to_tag(tag)
        end
      end
    end,
  }),
  awful.key({
    modifiers = { modkey, "Control", "Shift" },
    keygroup = "numrow",
    description = "toggle focused client on tag",
    group = "tag",
    on_press = function(index)
      if client.focus then
        local tag = client.focus.screen.tags[index]
        if tag then
          client.focus:toggle_tag(tag)
        end
      end
    end,
  }),
  awful.key({
    modifiers = { modkey },
    keygroup = "numpad",
    description = "select layout directly",
    group = "layout",
    on_press = function(index)
      local t = awful.screen.focused().selected_tag
      if t then
        t.layout = t.layouts[index] or t.layout
      end
    end,
  }),
})

client.connect_signal("request::default_mousebindings", function()
  awful.mouse.append_client_mousebindings({
    awful.button({}, 1, function(c)
      c:activate({ context = "mouse_click" })
    end),
    awful.button({ modkey }, 1, function(c)
      c:activate({ context = "mouse_click", action = "mouse_move" })
    end),
    awful.button({ modkey }, 3, function(c)
      c:activate({ context = "mouse_click", action = "mouse_resize" })
    end),
  })
end)

client.connect_signal("request::default_keybindings", function()
  awful.keyboard.append_client_keybindings({
    awful.key({ modkey }, "f", function(c)
      c.fullscreen = not c.fullscreen
      c:raise()
    end, { description = "toggle fullscreen", group = "client" }),
    awful.key({ modkey, "Shift" }, "c", function(c)
      c:kill()
    end, { description = "close", group = "client" }),
    awful.key(
      { modkey, "Control" },
      "space",
      awful.client.floating.toggle,
      { description = "toggle floating", group = "client" }
    ),
    awful.key({ modkey }, "Return", function(c)
      c:swap(awful.client.getmaster())
    end, { description = "move to master", group = "client" }),
    --awful.key({ modkey,           }, "o",      function (c) c:move_to_screen()               end,
    --        {description = "move to screen", group = "client"}),
    awful.key({ modkey }, "t", function(c)
      c.ontop = not c.ontop
    end, { description = "toggle keep on top", group = "client" }),
    awful.key({ modkey }, "n", function(c)
      -- The client currently has the input focus, so it cannot be
      -- minimized, since minimized clients can't have the focus.
      c.minimized = true
    end, { description = "minimize", group = "client" }),
    awful.key({ modkey }, "m", function(c)
      c.maximized = not c.maximized
      c:raise()
    end, { description = "(un)maximize", group = "client" }),
    awful.key({ modkey, "Control" }, "m", function(c)
      c.maximized_vertical = not c.maximized_vertical
      c:raise()
    end, { description = "(un)maximize vertically", group = "client" }),
    awful.key({ modkey, "Shift" }, "m", function(c)
      c.maximized_horizontal = not c.maximized_horizontal
      c:raise()
    end, { description = "(un)maximize horizontally", group = "client" }),
    awful.key({ modkey }, ",", function(c)
    end),
    awful.key({ modkey,           }, "o", 
    function (c) 
        local c = c or client.focus
        c:move_to_screen(screen[c.screen.index % screen.count() + 1])
    end,
    {description = "move to other screen", group = "client"})
  })
end)

-- }}}

-- {{{ Rules
-- Rules to apply to new clients.
ruled.client.connect_signal("request::rules", function()
  -- All clients will match this rule.
  ruled.client.append_rule({
    id = "global",
    rule = {},
    properties = {
      focus = awful.client.focus.filter,
      raise = true,
      screen = awful.screen.preferred,
      placement = awful.placement.no_overlap + awful.placement.no_offscreen,
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 8)
      end,
    },
  })

  -- Floating clients.
  ruled.client.append_rule({
    id = "floating",
    rule_any = {
      instance = { "copyq", "pinentry" },
      class = {
        "Arandr",
        "Blueman-manager",
        "Gpick",
        "Kruler",
        "Sxiv",
        "Tor Browser",
        "Wpa_gui",
        "veromix",
        "xtightvncviewer",
      },
      -- Note that the name property shown in xprop might be set slightly after creation of the client
      -- and the name shown there might not match defined rules here.
      name = {
        "Event Tester", -- xev.
      },
      role = {
        "AlarmWindow", -- Thunderbird's calendar.
        "ConfigManager", -- Thunderbird's about:config.
        "pop-up",    -- e.g. Google Chrome's (detached) Developer Tools.
      },
    },
    properties = { floating = true },
  })

  -- Add titlebars to normal clients and dialogs
  --ruled.client.append_rule {
  --    id         = "titlebars",
  --    rule_any   = { type = { "normal", "dialog" } },
  --    properties = { titlebars_enabled = true      }
  --}

  -- Set Firefox to always map on the tag named "2" on screen 1.
  -- ruled.client.append_rule {
  --     rule       = { class = "Firefox"     },
  --     properties = { screen = 1, tag = "2" }
  -- }
end)
-- }}}

-- {{{ Titlebars
-- Add a titlebar if titlebars_enabled is set to true in the rules.
client.connect_signal("request::titlebars", function(c)
  -- buttons for the titlebar
  local buttons = {
    awful.button({}, 1, function()
      c:activate({ context = "titlebar", action = "mouse_move" })
    end),
    awful.button({}, 3, function()
      c:activate({ context = "titlebar", action = "mouse_resize" })
    end),
  }

  awful.titlebar(c).widget = {
    {
    -- Left
      awful.titlebar.widget.iconwidget(c),
      buttons = buttons,
      layout = wibox.layout.fixed.horizontal,
    },
    {
     -- Middle
      {
      -- Title
        align = "center",
        widget = awful.titlebar.widget.titlewidget(c),
      },
      buttons = buttons,
      layout = wibox.layout.flex.horizontal,
    },
    {
    -- Right
      awful.titlebar.widget.floatingbutton(c),
      awful.titlebar.widget.maximizedbutton(c),
      awful.titlebar.widget.stickybutton(c),
      awful.titlebar.widget.ontopbutton(c),
      awful.titlebar.widget.closebutton(c),
      layout = wibox.layout.fixed.horizontal(),
    },
    layout = wibox.layout.align.horizontal,
  }
end)
-- }}}

-- {{{ Notifications

ruled.notification.connect_signal("request::rules", function()
  -- All notifications will match this rule.
  ruled.notification.append_rule({
    rule = {},
    properties = {
      screen = awful.screen.preferred,
      implicit_timeout = 5,
    },
  })
end)

naughty.connect_signal("request::display", function(n)
  naughty.layout.box({ notification = n })
end)

-- }}}

-- Enable sloppy focus, so that focus follows mouse.
client.connect_signal("mouse::enter", function(c)
  c:activate({ context = "mouse_enter", raise = false })
end)

-- Spawn background stuff that im too lazy to create .service files for
awesome.spawn("setxkbmap us intl", false)
awesome.spawn("pkill pipewire", false)
awesome.spawn("nm-applet", false)
awesome.spawn("syncthing", false)
awesome.spawn("xsettingsd", false)
awesome.spawn("touchegg", false)
awesome.spawn("xmousepasteblock", false)
awesome.spawn("mpris-proxy", false)
