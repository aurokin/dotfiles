local FOCUS_DELAY_SEC = 0.01
local FOCUS_POLL_INTERVAL_SEC = 0.02
local FOCUS_POLL_MAX_SEC = 1.0
local MOVE_PRE_SWITCH_DELAY_SEC = 0.2
local MOVE_SWITCH_DELAY_SEC = 0.05
local MOVE_DROP_DELAY_SEC = 0.2
local MOVE_MAXIMIZE_DELAY_SEC = 0.02
local MOVE_RETURN_TO_ORIGINAL = false
local MOVE_DRAG_TIMEOUT_SEC = 1.0

local homeDir = os.getenv("HOME") or ""
local SAFE_MODE = homeDir ~= "" and hs.fs.attributes(homeDir .. "/.hammerspoon/SAFE_MODE") ~= nil
local ENABLE_SPACE_ACTION_LOG = false
local ACTION_LOG_FILE = homeDir ~= "" and (homeDir .. "/.hammerspoon/space-actions.log") or nil

local FOCUS_MODIFIERS = { alt = true }
-- NOTE: Option+Shift+number is easy to hit accidentally (e.g. typing symbols
-- with Shift+number while Option is still held). Make moves more deliberate.
local MOVE_MODIFIERS = { alt = true, ctrl = true, shift = true }
local MOVE_SWITCH_MODIFIERS = { alt = true }
local MODIFIER_KEYS = { "alt", "cmd", "ctrl", "shift", "fn" }

local DEBUG_SPACE = false
local log = hs.logger.new("spaces", DEBUG_SPACE and "debug" or "warning")
local pendingFocusTimer = nil
local pendingFocusPollTimer = nil
local pendingMove = nil
local focusRequestSeq = 0

local function writeActionLog(message)
  if not ENABLE_SPACE_ACTION_LOG or not ACTION_LOG_FILE then
    return
  end

  local file = io.open(ACTION_LOG_FILE, "a")
  if not file then
    return
  end

  file:write(string.format("%s %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
  file:close()
end

local function activeSpacesToString(activeSpaces)
  local parts = {}
  for uuid, spaceId in pairs(activeSpaces or {}) do
    parts[#parts + 1] = string.format("%s=%s", tostring(uuid), tostring(spaceId))
  end
  table.sort(parts)
  return table.concat(parts, ", ")
end

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

local function readSpacesPlistJson()
  if homeDir == "" then
    return nil
  end

  local plistPath = homeDir .. "/Library/Preferences/com.apple.spaces.plist"
  local cmd = string.format("/usr/bin/plutil -convert json -o - %q 2>/dev/null", plistPath)
  local pipe = io.popen(cmd)
  if not pipe then
    return nil
  end

  local out = pipe:read("*a")
  pipe:close()
  if not out or out == "" then
    return nil
  end

  return hs.json.decode(out)
end

local function nativeDesktopOrder()
  local decoded = readSpacesPlistJson()
  if not decoded then
    return nil
  end

  local spacesConfig = decoded["SpacesDisplayConfiguration"]
  local managementData = spacesConfig and spacesConfig["Management Data"]
  local monitors = managementData and managementData["Monitors"]
  if type(monitors) ~= "table" then
    return nil
  end

  local ordered = {}
  for _, monitor in ipairs(monitors) do
    local displayId = monitor["Display Identifier"]
    for _, space in ipairs(monitor["Spaces"] or {}) do
      local spaceId = space["ManagedSpaceID"]
      if spaceId and hs.spaces.spaceType(spaceId) == "user" then
        local displayUuid = hs.spaces.spaceDisplay(spaceId)
        if not displayUuid and displayId ~= "Main" then
          displayUuid = displayId
        end
        ordered[#ordered + 1] = {
          space = spaceId,
          display = displayUuid,
        }
      end
    end
  end

  if #ordered == 0 then
    return nil
  end

  return ordered
end

local function orderedSpacesToString()
  local native = nativeDesktopOrder()
  if native then
    local parts = {}
    for i, entry in ipairs(native) do
      parts[#parts + 1] = string.format("%d:%s@%s", i, tostring(entry.space), tostring(entry.display))
    end
    return table.concat(parts, " ")
  end

  local ordered, _, displayBy = spaceInfo()
  local parts = {}
  for i, spaceId in ipairs(ordered) do
    parts[#parts + 1] = string.format("%d:%s@%s", i, tostring(spaceId), tostring(displayBy[spaceId]))
  end
  return table.concat(parts, " ")
end

local function spaceForIndex(index)
  local native = nativeDesktopOrder()
  if native and native[index] then
    return native[index].space, native[index].display
  end

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

local function focusWindowForSpace(space)
  local windowIds = hs.spaces.windowsForSpace(space)
  if not windowIds then
    return false
  end

  for _, windowId in ipairs(windowIds) do
    local win = hs.window.get(windowId)
    if win and win:isStandard() then
      win:focus()
      return true
    end
  end

  return false
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

local function focusVisibleStandardWindowOnDisplay(displayUuid)
  if not displayUuid then
    return false
  end

  for _, win in ipairs(hs.window.visibleWindows()) do
    if win and win:isStandard() then
      local screen = win:screen()
      if screen and screen:getUUID() == displayUuid then
        win:focus()
        return true
      end
    end
  end

  return false
end

local function clickDisplay(displayUuid)
  if not displayUuid then
    return false
  end

  local screen = hs.screen.find(displayUuid)
  if not screen then
    return false
  end

  local frame = screen:fullFrame()
  local clickPoint = {
    x = math.floor(frame.x + frame.w / 2),
    y = math.floor(frame.y + 8),
  }
  local originalMouse = hs.mouse.absolutePosition()

  hs.mouse.absolutePosition(clickPoint)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, clickPoint):post()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, clickPoint):post()
  hs.mouse.absolutePosition(originalMouse)
  return true
end

local function focusSpaceAndDisplay(spaceId, displayUuid)
  local focusedWin = hs.window.focusedWindow()
  local focusedScreen = focusedWin and focusedWin:screen() or nil
  local focusedDisplay = focusedScreen and focusedScreen:getUUID() or nil

  -- Prioritize selecting the display first; this is noticeably faster than
  -- focusing by window ID when the target space is already active elsewhere.
  if displayUuid and focusedDisplay ~= displayUuid then
    if clickDisplay(displayUuid) then
      return "display-click"
    end
  end

  local focusBySpace = focusWindowForSpace(spaceId)
  if focusBySpace then
    return "space-window"
  end

  local focusByDisplay = focusVisibleStandardWindowOnDisplay(displayUuid)
  if focusByDisplay then
    return "display-window"
  end

  local clickedDisplay = clickDisplay(displayUuid)
  if clickedDisplay then
    return "display-click"
  end

  if focusVisibleStandardWindow() then
    return "fallback-window"
  end

  return "none"
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

local function stopPendingFocusTimers()
  focusRequestSeq = focusRequestSeq + 1
  if pendingFocusTimer then
    pendingFocusTimer:stop()
    pendingFocusTimer = nil
  end
  if pendingFocusPollTimer then
    pendingFocusPollTimer:stop()
    pendingFocusPollTimer = nil
  end
end

local function changedDisplaySpace(previousActive, currentActive)
  for displayUuid, spaceId in pairs(currentActive or {}) do
    if previousActive[displayUuid] ~= spaceId then
      return displayUuid, spaceId, previousActive[displayUuid]
    end
  end
  return nil, nil, nil
end

local function followNativeSpaceSwitch(requestId, index, flags, baselineFocusedSpace, baselineActiveSpaces)
  local baselineDisplay = baselineFocusedSpace and hs.spaces.spaceDisplay(baselineFocusedSpace) or nil
  local mappedSpace, mappedDisplay = spaceForIndex(index)

  writeActionLog(string.format(
    "focus begin index=%d flags=%s baselineFocused=%s baselineDisplay=%s mappedSpace=%s mappedDisplay=%s ordered=[%s] active={%s}",
    index,
    tostring(flags),
    tostring(baselineFocusedSpace),
    tostring(baselineDisplay),
    tostring(mappedSpace),
    tostring(mappedDisplay),
    orderedSpacesToString(),
    activeSpacesToString(baselineActiveSpaces)
  ))

  local startedAt = hs.timer.secondsSinceEpoch()
  local attempts = 0

  pendingFocusPollTimer = hs.timer.doEvery(FOCUS_POLL_INTERVAL_SEC, function()
    if requestId ~= focusRequestSeq then
      stopPendingFocusTimers()
      return
    end

    attempts = attempts + 1
    local nowFocused = hs.spaces.focusedSpace()
    local nowActive = hs.spaces.activeSpaces() or {}
    local changedDisplay, changedSpace, previousSpace = changedDisplaySpace(baselineActiveSpaces, nowActive)
    local mappedIsAlreadyActive = mappedSpace and mappedDisplay and nowActive[mappedDisplay] == mappedSpace

    if attempts <= 8 or attempts % 5 == 0 then
      writeActionLog(string.format(
        "focus poll index=%d attempt=%d focused=%s changedDisplay=%s changedSpace=%s previousSpace=%s mappedActive=%s",
        index,
        attempts,
        tostring(nowFocused),
        tostring(changedDisplay),
        tostring(changedSpace),
        tostring(previousSpace),
        tostring(mappedIsAlreadyActive)
      ))
    end

    if changedDisplay and changedSpace then
      local mode = focusSpaceAndDisplay(changedSpace, changedDisplay)
      writeActionLog(string.format(
        "focus done index=%d mode=%s changedDisplay=%s changedSpace=%s focused=%s active={%s}",
        index,
        mode,
        tostring(changedDisplay),
        tostring(changedSpace),
        tostring(hs.spaces.focusedSpace()),
        activeSpacesToString(hs.spaces.activeSpaces() or {})
      ))
      stopPendingFocusTimers()
      return
    end

    -- Native shortcut sometimes keeps activeSpaces unchanged when the target
    -- desktop is already active on another display. In that case, select the
    -- mapped display directly.
    if mappedIsAlreadyActive then
      local mode = focusSpaceAndDisplay(mappedSpace, mappedDisplay)
      writeActionLog(string.format(
        "focus done-mapped index=%d mode=%s mappedDisplay=%s mappedSpace=%s focused=%s active={%s}",
        index,
        mode,
        tostring(mappedDisplay),
        tostring(mappedSpace),
        tostring(hs.spaces.focusedSpace()),
        activeSpacesToString(hs.spaces.activeSpaces() or {})
      ))
      stopPendingFocusTimers()
      return
    end

    if nowFocused and nowFocused ~= baselineFocusedSpace then
      local focusedDisplay = hs.spaces.spaceDisplay(nowFocused)
      local mode = focusSpaceAndDisplay(nowFocused, focusedDisplay)
      writeActionLog(string.format(
        "focus done-fallback index=%d mode=%s focused=%s focusedDisplay=%s active={%s}",
        index,
        mode,
        tostring(nowFocused),
        tostring(focusedDisplay),
        activeSpacesToString(hs.spaces.activeSpaces() or {})
      ))
      stopPendingFocusTimers()
      return
    end

    local elapsed = hs.timer.secondsSinceEpoch() - startedAt
    if elapsed >= FOCUS_POLL_MAX_SEC then
      local timeoutMode = "none"
      if mappedSpace and mappedDisplay then
        timeoutMode = focusSpaceAndDisplay(mappedSpace, mappedDisplay)
      end
      writeActionLog(string.format(
        "focus timeout index=%d mode=%s focused=%s active={%s}",
        index,
        timeoutMode,
        tostring(hs.spaces.focusedSpace()),
        activeSpacesToString(hs.spaces.activeSpaces() or {})
      ))
      stopPendingFocusTimers()
    end
  end)

  return true
end

local keycodeToIndex = {}
for i = 1, 9 do
  keycodeToIndex[hs.keycodes.map[tostring(i)]] = i
end

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

      writeActionLog(string.format("move keyDown index=%d flags=%s", index, flagsToString(flags)))
      stopPendingFocusTimers()

      local win = hs.window.frontmostWindow()
      if moveWindowToSpaceCrossDisplay(win, index) then
        writeActionLog(string.format("move cross-display index=%d result=true", index))
        return true
      end

      pendingMove = startWindowDrag(win, index)
      writeActionLog(string.format("move drag-start index=%d result=%s", index, tostring(pendingMove ~= nil)))
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

    stopPendingFocusTimers()
    writeActionLog(string.format("focus keyDown index=%d flags=%s", index, flagsToString(flags)))

    if isFocusSuppressed() then
      writeActionLog(string.format("focus keyDown index=%d suppressed=true", index))
      return false
    end

    local baselineFocusedSpace = hs.spaces.focusedSpace()
    local baselineActiveSpaces = hs.spaces.activeSpaces() or {}
    local mappedSpace, mappedDisplay = spaceForIndex(index)
    local baselineDisplay = baselineFocusedSpace and hs.spaces.spaceDisplay(baselineFocusedSpace) or nil
    local requestId = focusRequestSeq

    if mappedSpace and mappedDisplay and mappedDisplay ~= baselineDisplay and baselineActiveSpaces[mappedDisplay] == mappedSpace then
      local mode = focusSpaceAndDisplay(mappedSpace, mappedDisplay)
      writeActionLog(string.format(
        "focus instant-mapped index=%d mode=%s mappedDisplay=%s mappedSpace=%s baselineDisplay=%s",
        index,
        mode,
        tostring(mappedDisplay),
        tostring(mappedSpace),
        tostring(baselineDisplay)
      ))
      return false
    end

    pendingFocusTimer = hs.timer.doAfter(FOCUS_DELAY_SEC, function()
      if requestId ~= focusRequestSeq then
        return
      end
      if isFocusSuppressed() then
        writeActionLog(string.format("focus timer index=%d suppressed=true", index))
        return
      end
      pendingFocusTimer = nil
      followNativeSpaceSwitch(requestId, index, flagsToString(flags), baselineFocusedSpace, baselineActiveSpaces)
    end)

    -- Keep native Option+number behavior from macOS. We only observe and follow
    -- the resulting switch to select the correct display.
    return false
  end

  if event:getType() == hs.eventtap.event.types.keyUp then
    if DEBUG_SPACE then
      dbg("keyUp %s flags=%s", tostring(index), flagsToString(flags))
    end
    if pendingMove and pendingMove.targetIndex == index then
      writeActionLog(string.format("move keyUp index=%d finish=true", index))
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

writeActionLog("---- reload ----")
writeActionLog("ordered-spaces " .. orderedSpacesToString())
writeActionLog("active-spaces {" .. activeSpacesToString(hs.spaces.activeSpaces() or {}) .. "}")

if SAFE_MODE then
  writeActionLog("startup safe_mode=true hotkeys-disabled")
  hs.alert.show("Hammerspoon SAFE_MODE: shortcuts disabled")
else
  writeActionLog("startup safe_mode=false starting-eventtap")
  spaceFocusOptionTap:start()
  writeActionLog("eventtap started")

  hs.hotkey.bind({ "alt" }, "return", function()
    writeActionLog("hotkey alt+return maximize")
    local win = hs.window.frontmostWindow()
    if win then
      win:maximize()
    end
  end)
end
