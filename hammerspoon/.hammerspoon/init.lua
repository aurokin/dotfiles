local FOCUS_DELAY_SEC = 0.2
local SPACE_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local FOCUS_MODIFIERS = { alt = true }
local MODIFIER_KEYS = { "alt", "cmd", "ctrl", "shift", "fn" }

local function focusWindowForSpace(space)
  local windowIds = hs.spaces.windowsForSpace(space)
  if windowIds then
    for _, windowId in ipairs(windowIds) do
      local win = hs.window.get(windowId)
      if win and win:isStandard() then
        win:focus()
        return true
      end
    end
  end

  return false
end

local function sortedScreens()
  local screens = hs.screen.allScreens()
  table.sort(screens, function(a, b)
    local fa = a:frame()
    local fb = b:frame()
    if fa.y == fb.y then
      return fa.x < fb.x
    end
    return fa.y < fb.y
  end)
  return screens
end

local function orderedSpaces()
  local spacesByScreen = hs.spaces.allSpaces()
  local ordered = {}
  for _, screen in ipairs(sortedScreens()) do
    local uuid = screen:getUUID()
    local spaces = spacesByScreen[uuid]
    if spaces then
      for _, space in ipairs(spaces) do
        if hs.spaces.spaceType(space) == "user" then
          table.insert(ordered, space)
        end
      end
    end
  end
  return ordered
end

local function modifiersMatch(flags)
  for _, key in ipairs(MODIFIER_KEYS) do
    local want = FOCUS_MODIFIERS[key] or false
    local have = flags[key] or false
    if have ~= want then
      return false
    end
  end
  return true
end

local keycodeToIndex = {}
for i, key in ipairs(SPACE_KEYS) do
  keycodeToIndex[hs.keycodes.map[key]] = i
end

local pendingFocusTimer = nil
spaceFocusOptionTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  if event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1 then
    return false
  end

  local flags = event:getFlags()
  if not modifiersMatch(flags) then
    return false
  end

  local index = keycodeToIndex[event:getKeyCode()]
  if not index then
    return false
  end


  if pendingFocusTimer then
    pendingFocusTimer:stop()
    pendingFocusTimer = nil
  end

  pendingFocusTimer = hs.timer.doAfter(FOCUS_DELAY_SEC, function()
    local spaces = orderedSpaces()
    local space = spaces[index]
    if space then
      focusWindowForSpace(space)
    end
  end)

  return false
end)

spaceFocusOptionTap:start()

hs.hotkey.bind({ "alt" }, "return", function()
  local win = hs.window.frontmostWindow()
  if win then
    win:maximize()
  end
end)
