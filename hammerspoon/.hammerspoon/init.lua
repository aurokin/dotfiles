local FOCUS_DELAY_SEC = 0.2
local MOVE_SWITCH_DELAY_SEC = 0.05
local MOVE_DROP_DELAY_SEC = 0.4
local MOVE_RETURN_TO_ORIGINAL = false
local SPACE_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local FOCUS_MODIFIERS = { alt = true }
local MOVE_MODIFIERS = { alt = true, shift = true }
local MOVE_SWITCH_MODIFIERS = { alt = true }
local MODIFIER_KEYS = { "alt", "cmd", "ctrl", "shift", "fn" }
local function modifiersToList(modifiers)
  local list = {}
  for _, key in ipairs(MODIFIER_KEYS) do
    if modifiers[key] then
      table.insert(list, key)
    end
  end
  return list
end

local MOVE_SWITCH_KEYS = modifiersToList(MOVE_SWITCH_MODIFIERS)

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

local function spaceIndex(spaceId)
  local spaces = orderedSpaces()
  for i, space in ipairs(spaces) do
    if space == spaceId then
      return i
    end
  end
  return nil
end

local function dragPointForWindow(win)
  local frame = win:frame()
  if not frame then
    return nil
  end

  local element = hs.axuielement.windowElement(win)
  if element then
    local minimize = element:attributeValue("AXMinimizeButton")
    if minimize then
      local minFrame = minimize:attributeValue("AXFrame")
      if minFrame then
        return {
          x = minFrame.x + minFrame.w / 2,
          y = frame.y + math.abs(frame.y - minFrame.y) / 2,
        }
      end
    end
  end

  return {
    x = math.min(frame.x + 20, frame.x + frame.w - 5),
    y = math.min(frame.y + 10, frame.y + frame.h - 5),
  }
end

local function startWindowDrag(win, targetIndex)
  if not win or win:isFullScreen() then
    return nil
  end

  local spaces = orderedSpaces()
  local space = spaces[targetIndex]
  if not space then
    return nil
  end

  local dragPoint = dragPointForWindow(win)
  if not dragPoint then
    return nil
  end

  local dragPoint2 = {
    x = dragPoint.x + 10,
    y = dragPoint.y + 5,
  }

  local originalMouse = hs.mouse.absolutePosition()
  local originalSpace = hs.spaces.focusedSpace()
  local originalIndex = originalSpace and spaceIndex(originalSpace) or nil

  hs.mouse.absolutePosition(dragPoint)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, dragPoint):post()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDragged, dragPoint2):post()

  return {
    win = win,
    targetIndex = targetIndex,
    dragPoint2 = dragPoint2,
    originalMouse = originalMouse,
    originalIndex = originalIndex,
  }
end

local function finishWindowDrag(pending)
  if not pending then
    return
  end

  hs.timer.doAfter(MOVE_SWITCH_DELAY_SEC, function()
    local keyDown = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(pending.targetIndex), true)
    local keyUp = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(pending.targetIndex), false)
    keyDown:post()
    keyUp:post()
    hs.timer.doAfter(MOVE_DROP_DELAY_SEC, function()
      hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pending.dragPoint2):post()
      if MOVE_RETURN_TO_ORIGINAL and pending.originalIndex and pending.originalIndex ~= pending.targetIndex then
        local backDown = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(pending.originalIndex), true)
        local backUp = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(pending.originalIndex), false)
        backDown:post()
        backUp:post()
      end
      if pending.win then
        pending.win:maximize()
      end
      if pending.originalMouse then
        hs.mouse.absolutePosition(pending.originalMouse)
      end
    end)
  end)
end

local function modifiersMatch(flags, modifiers)
  for _, key in ipairs(MODIFIER_KEYS) do
    local want = modifiers[key] or false
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
local pendingMove = nil
spaceFocusOptionTap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.keyUp,
}, function(event)
  if event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1 then
    return false
  end

  local index = keycodeToIndex[event:getKeyCode()]
  if not index then
    return false
  end

  local flags = event:getFlags()
  if event:getType() == hs.eventtap.event.types.keyDown then
    if modifiersMatch(flags, MOVE_MODIFIERS) then
      pendingMove = startWindowDrag(hs.window.frontmostWindow(), index)
      return true
    end

    if not modifiersMatch(flags, FOCUS_MODIFIERS) then
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
  end

  if event:getType() == hs.eventtap.event.types.keyUp then
    if pendingMove and modifiersMatch(flags, MOVE_MODIFIERS) then
      finishWindowDrag(pendingMove)
      pendingMove = nil
      return true
    end

    return false
  end

  return false
end)

spaceFocusOptionTap:start()

hs.hotkey.bind({ "alt" }, "return", function()
  local win = hs.window.frontmostWindow()
  if win then
    win:maximize()
  end
end)
