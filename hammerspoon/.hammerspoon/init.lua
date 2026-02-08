local FOCUS_DELAY_SEC = 0.05
local FOCUS_RETRY_DELAY_SEC = 0.25
local MOVE_PRE_SWITCH_DELAY_SEC = 0.2
local MOVE_SWITCH_DELAY_SEC = 0.05
local MOVE_DROP_DELAY_SEC = 0.2
local MOVE_MAXIMIZE_DELAY_SEC = 0.02
local MOVE_RETURN_TO_ORIGINAL = false
local MOVE_DRAG_TIMEOUT_SEC = 1.0

local homeDir = os.getenv("HOME") or ""
local SAFE_MODE = homeDir ~= "" and hs.fs.attributes(homeDir .. "/.hammerspoon/SAFE_MODE") ~= nil

local FOCUS_MODIFIERS = { alt = true }
-- NOTE: Option+Shift+number is easy to hit accidentally (e.g. typing symbols
-- with Shift+number while Option is still held). Make moves more deliberate.
local MOVE_MODIFIERS = { alt = true, ctrl = true, shift = true }
local MOVE_SWITCH_MODIFIERS = { alt = true }
local MODIFIER_KEYS = { "alt", "cmd", "ctrl", "shift", "fn" }

local DEBUG_SPACE = false
local log = hs.logger.new("spaces", DEBUG_SPACE and "debug" or "warning")

local suppressFocusUntil = 0
local function nowSec()
  return hs.timer.secondsSinceEpoch()
end

local function suppressFocusFor(sec)
  suppressFocusUntil = math.max(suppressFocusUntil, nowSec() + sec)
end

local function isFocusSuppressed()
  return nowSec() < suppressFocusUntil
end

local function dbg(fmt, ...)
  if not DEBUG_SPACE then
    return
  end
  log.df(fmt, ...)
end

local function flagsToString(flags)
  local parts = {}
  for _, key in ipairs(MODIFIER_KEYS) do
    if flags[key] then
      parts[#parts + 1] = key
    end
  end
  return table.concat(parts, "+")
end

local lastNumberChord = nil
local debugSpaceWatcherTimer = nil
if DEBUG_SPACE then
  local lastSpace = hs.spaces.focusedSpace()
  debugSpaceWatcherTimer = hs.timer.doEvery(0.1, function()
    local current = hs.spaces.focusedSpace()
    if current ~= lastSpace then
      local chord = lastNumberChord
      local chordStr = chord
          and string.format("%s %s (%s)", tostring(chord.index), tostring(chord.action), tostring(chord.flags))
        or "<none>"
      dbg("space change %s -> %s; last chord: %s", tostring(lastSpace), tostring(current), chordStr)
      lastSpace = current
    end
  end)
end

local function modifiersToList(modifiers)
  local list = {}
  for _, key in ipairs(MODIFIER_KEYS) do
    if modifiers[key] then
      list[#list + 1] = key
    end
  end
  return list
end

local MOVE_SWITCH_KEYS = modifiersToList(MOVE_SWITCH_MODIFIERS)

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

local function spaceInfo()
  local spacesByScreen = hs.spaces.allSpaces()
  local ordered = {}
  local indexBy = {}
  local displayBy = {}

  for _, screen in ipairs(sortedScreens()) do
    local uuid = screen:getUUID()
    local spaces = spacesByScreen[uuid]
    if spaces then
      for _, space in ipairs(spaces) do
        if hs.spaces.spaceType(space) == "user" then
          ordered[#ordered + 1] = space
          indexBy[space] = #ordered
          displayBy[space] = uuid
        end
      end
    end
  end

  return ordered, indexBy, displayBy
end

local function spaceForIndex(index)
  local ordered, _, displayBy = spaceInfo()
  local space = ordered[index]
  if not space then
    return nil
  end
  return space, displayBy[space]
end

local function indexForSpace(spaceId)
  local _, indexBy = spaceInfo()
  return indexBy[spaceId]
end

local function switchToSpaceIndex(index)
  -- We generate Option+number events to trigger macOS's Space switching. Those
  -- synthetic events are also seen by our own eventtap; suppress focus logic so
  -- moves don't schedule extra work.
  suppressFocusFor(0.25)
  local keyDown = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(index), true)
  local keyUp = hs.eventtap.event.newKeyEvent(MOVE_SWITCH_KEYS, tostring(index), false)
  keyDown:post()
  keyUp:post()
end

local function focusVisibleStandardWindow()
  local focused = hs.window.focusedWindow()
  if focused and focused:isStandard() then
    return true
  end

  local frontmost = hs.window.frontmostWindow()
  if frontmost and frontmost:isStandard() then
    frontmost:focus()
    return true
  end

  for _, win in ipairs(hs.window.visibleWindows()) do
    if win and win:isStandard() then
      win:focus()
      return true
    end
  end

  return false
end

local function maximizeWindowById(winId, winPid, winTitle)
  if not winId then
    return
  end

  local win = hs.window.get(winId)
  if not win and winPid and winTitle then
    local app = hs.application.get(winPid)
    if app then
      for _, candidate in ipairs(app:allWindows()) do
        if candidate:title() == winTitle then
          win = candidate
          break
        end
      end
    end
  end

  if win then
    win:focus()
    win:maximize()
  end
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

  local targetSpace = spaceForIndex(targetIndex)
  if not targetSpace then
    return nil
  end

  local dragPoint = dragPointForWindow(win)
  if not dragPoint then
    return nil
  end

  local winId = win:id()
  if not winId then
    return nil
  end

  local app = win:application()
  local winPid = app and app:pid() or nil
  local winTitle = win:title()

  local dragPoint2 = {
    x = dragPoint.x + 10,
    y = dragPoint.y + 5,
  }

  local originalMouse = hs.mouse.absolutePosition()
  local originalSpace = hs.spaces.focusedSpace()
  local originalIndex = originalSpace and indexForSpace(originalSpace) or nil

  hs.mouse.absolutePosition(dragPoint)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, dragPoint):post()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDragged, dragPoint2):post()

  return {
    winId = winId,
    winPid = winPid,
    winTitle = winTitle,
    targetIndex = targetIndex,
    targetSpace = targetSpace,
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
    switchToSpaceIndex(pending.targetIndex)
    hs.timer.doAfter(MOVE_DROP_DELAY_SEC, function()
      hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pending.dragPoint2):post()
      if pending.targetSpace then
        hs.spaces.moveWindowToSpace(pending.winId, pending.targetSpace, true)
      end
      if MOVE_RETURN_TO_ORIGINAL and pending.originalIndex and pending.originalIndex ~= pending.targetIndex then
        switchToSpaceIndex(pending.originalIndex)
      end
      hs.timer.doAfter(MOVE_MAXIMIZE_DELAY_SEC, function()
        maximizeWindowById(pending.winId, pending.winPid, pending.winTitle)
      end)
      if pending.originalMouse then
        hs.mouse.absolutePosition(pending.originalMouse)
      end
    end)
  end)
end

local function moveWindowToSpaceCrossDisplay(win, targetIndex)
  if not win or win:isFullScreen() then
    return false
  end

  local winId = win:id()
  if not winId then
    return false
  end

  local space, targetDisplay = spaceForIndex(targetIndex)
  if not space or not targetDisplay then
    return false
  end

  local currentScreen = win:screen()
  local currentDisplay = currentScreen and currentScreen:getUUID() or nil
  if not currentDisplay or targetDisplay == currentDisplay then
    return false
  end

  local app = win:application()
  local winPid = app and app:pid() or nil
  local winTitle = win:title()

  switchToSpaceIndex(targetIndex)
  hs.timer.doAfter(MOVE_PRE_SWITCH_DELAY_SEC, function()
    local targetScreen = hs.screen.find(targetDisplay)
    if targetScreen and win:screen() ~= targetScreen then
      win:moveToScreen(targetScreen)
    end

    hs.timer.doAfter(MOVE_SWITCH_DELAY_SEC, function()
      hs.spaces.moveWindowToSpace(winId, space, true)
      hs.timer.doAfter(MOVE_MAXIMIZE_DELAY_SEC, function()
        maximizeWindowById(winId, winPid, winTitle)
      end)
    end)
  end)

  return true
end

local keycodeToIndex = {}
for i = 1, 9 do
  keycodeToIndex[hs.keycodes.map[tostring(i)]] = i
end

local pendingFocusTimer = nil
local pendingFocusRetryTimer = nil
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
    if DEBUG_SPACE then
      lastNumberChord = {
        t = hs.timer.secondsSinceEpoch(),
        index = index,
        flags = flagsToString(flags),
        action = "pass",
      }
      dbg("keyDown %s flags=%s", tostring(index), tostring(lastNumberChord.flags))
    end

    if modifiersMatch(flags, MOVE_MODIFIERS) then
      if lastNumberChord then
        lastNumberChord.action = "move"
      end

      if pendingFocusTimer then
        pendingFocusTimer:stop()
        pendingFocusTimer = nil
      end
      if pendingFocusRetryTimer then
        pendingFocusRetryTimer:stop()
        pendingFocusRetryTimer = nil
      end

      local win = hs.window.frontmostWindow()
      if moveWindowToSpaceCrossDisplay(win, index) then
        return true
      end

      pendingMove = startWindowDrag(win, index)
      if pendingMove then
        local moveRef = pendingMove
        moveRef.timeoutTimer = hs.timer.doAfter(MOVE_DRAG_TIMEOUT_SEC, function()
          if pendingMove ~= moveRef then
            return
          end
          hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, moveRef.dragPoint2):post()
          if moveRef.originalMouse then
            hs.mouse.absolutePosition(moveRef.originalMouse)
          end
          pendingMove = nil
        end)
      end
      return pendingMove ~= nil
    end

    if not modifiersMatch(flags, FOCUS_MODIFIERS) then
      return false
    end

    if lastNumberChord then
      lastNumberChord.action = "focus"
    end

    if pendingFocusTimer then
      pendingFocusTimer:stop()
      pendingFocusTimer = nil
    end
    if pendingFocusRetryTimer then
      pendingFocusRetryTimer:stop()
      pendingFocusRetryTimer = nil
    end

    if isFocusSuppressed() then
      return false
    end

    pendingFocusTimer = hs.timer.doAfter(FOCUS_DELAY_SEC, function()
      if isFocusSuppressed() then
        return
      end
      focusVisibleStandardWindow()
    end)

    pendingFocusRetryTimer = hs.timer.doAfter(FOCUS_DELAY_SEC + FOCUS_RETRY_DELAY_SEC, function()
      if isFocusSuppressed() then
        return
      end
      focusVisibleStandardWindow()
    end)

    return false
  end

  if event:getType() == hs.eventtap.event.types.keyUp then
    if DEBUG_SPACE then
      dbg("keyUp %s flags=%s", tostring(index), flagsToString(flags))
    end
    if pendingMove and pendingMove.targetIndex == index then
      if pendingMove.timeoutTimer then
        pendingMove.timeoutTimer:stop()
        pendingMove.timeoutTimer = nil
      end
      finishWindowDrag(pendingMove)
      pendingMove = nil
      return true
    end
  end

  return false
end)

if SAFE_MODE then
  hs.alert.show("Hammerspoon SAFE_MODE: shortcuts disabled")
else
  spaceFocusOptionTap:start()

  hs.hotkey.bind({ "alt" }, "return", function()
    local win = hs.window.frontmostWindow()
    if win then
      win:maximize()
    end
  end)
end
