-- Voice Dictation via whisper.cpp
-- Trigger: tap Right Command (press and release alone, quickly)

-- =====================================================
-- Voice Dictation — v2 (whisper-server HTTP + system media pause)
-- Trigger: tap Right Command (press and release quickly, alone)
-- =====================================================

local SOX_BIN = "/opt/homebrew/bin/sox"
local AUDIO_FILE = "/tmp/voice-capture.wav"
local LANGUAGE = "fa"
local WHISPER_SERVER = "http://localhost:8080/inference"
local PAUSE_MEDIA = true
local DEBUG = false  -- set true to write /tmp/hammerspoon-dictation.log
local SOUND_START = "/System/Library/Sounds/Pop.aiff"
local SOUND_STOP = "/System/Library/Sounds/Tink.aiff"
local SOUND_DONE = "/System/Library/Sounds/Glass.aiff"
local SOUND_ERROR = "/System/Library/Sounds/Sosumi.aiff"

-- =====================================================
-- Custom vocabulary corrections (add your own!)
-- Maps CORRECT spelling -> list of common mishearings.
-- After transcription, each mishearing in the text is replaced.
-- =====================================================
local CORRECTIONS = {
    ["VSCode"]      = { "وی اس کد", "ویاسکد" },
    ["GitHub"]      = { "گیت هاب", "گیتهاب", "گیت‌هاب" },
    ["Claude"]      = { "کلاود", "کلود" },
    ["Hammerspoon"] = { "هامرسپون", "همرسپون" },
    -- Add your project-specific words here, e.g.:
    -- ["MyStartup"] = { "مای استارتاپ", "مای استارت اپ" },
}

-- ============================================================
-- State & Menubar Indicator
-- ============================================================
local state = "idle" -- idle | recording | transcribing
local recordingTask = nil
local rightCmdDownTime = 0
local otherKeyPressed = false
local TAP_MAX_DURATION = 0.8
local wasMediaPlaying = false
local targetApp = nil
local targetAppName = nil

local menubar = hs.menubar.new()

local function updateMenubar()
    if state == "recording" then
        menubar:setTitle("● REC")
        menubar:setTooltip("Recording — tap Right Command to stop")
    elseif state == "transcribing" then
        menubar:setTitle("⋯ …")
        menubar:setTooltip("Transcribing…")
    else
        menubar:setTitle("◌ mic")
        menubar:setTooltip("Voice dictation idle — tap Right Command to start")
    end
end

local function flash(text, color, duration)
    hs.alert.closeAll()
    hs.alert.show(text, {
        textSize = 18,
        textFont = ".AppleSystemUIFont",
        fillColor = color,
        strokeColor = { white = 1, alpha = 0 },
        textColor = { white = 1 },
        radius = 10,
        atScreenEdge = 0,
    }, duration or 0)
end

-- ============================================================
-- Vocabulary corrections
-- ============================================================
local function applyCorrections(text)
    for correct, wrongs in pairs(CORRECTIONS) do
        for _, wrong in ipairs(wrongs) do
            text = text:gsub(wrong, correct)
        end
    end
    return text
end

-- ============================================================
-- Pause / resume media (system-wide — browsers, Music, Spotify, YouTube, etc.)
-- Uses nowplaying-cli which queries macOS MediaRemote framework.
-- ============================================================
local NOWPLAYING_BIN = "/opt/homebrew/bin/nowplaying-cli"

local function isMediaPlaying()
    -- playbackRate: "1" = playing, "0" = paused, empty = nothing
    local output, status = hs.execute(NOWPLAYING_BIN .. " get playbackRate 2>/dev/null")
    if not status then return false end
    return output and output:match("^%s*1%s*$") ~= nil
end

local function sendPlayPause()
    -- nowplaying-cli pause / play / togglePlayPause work system-wide including browsers
    hs.execute(NOWPLAYING_BIN .. " togglePlayPause 2>/dev/null")
end

-- ============================================================
-- Recording
-- ============================================================
-- Persistent recording indicator (pulsing red banner at top center)
local recordingIndicator = nil
local pulseTimer = nil

local function showRecordingIndicator()
    local screen = hs.screen.mainScreen():frame()
    local w, h = 260, 56
    local frame = {
        x = screen.x + (screen.w - w) / 2,
        y = screen.y + 8,
        w = w, h = h,
    }
    recordingIndicator = hs.canvas.new(frame)
    recordingIndicator:appendElements(
        {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.9, green = 0.1, blue = 0.1, alpha = 0.95 },
            roundedRectRadii = { xRadius = 12, yRadius = 12 },
        },
        {
            type = "circle",
            action = "fill",
            fillColor = { white = 1, alpha = 1 },
            center = { x = 24, y = h / 2 },
            radius = 8,
            id = "dot",
        },
        {
            type = "text",
            text = "RECORDING",
            textSize = 17,
            textColor = { white = 1, alpha = 1 },
            textFont = ".AppleSystemUIFont-Bold",
            textAlignment = "left",
            frame = { x = 48, y = 14, w = w - 56, h = h - 20 },
        }
    )
    recordingIndicator:behavior({ "canJoinAllSpaces", "stationary" })
    recordingIndicator:level("overlay")
    recordingIndicator:show()

    -- Pulse animation
    local pulseOn = true
    pulseTimer = hs.timer.doEvery(0.5, function()
        if recordingIndicator then
            recordingIndicator["dot"].fillColor = {
                white = 1, alpha = pulseOn and 1 or 0.35,
            }
            pulseOn = not pulseOn
        end
    end)
end

local function hideRecordingIndicator()
    if pulseTimer then pulseTimer:stop(); pulseTimer = nil end
    if recordingIndicator then recordingIndicator:delete(); recordingIndicator = nil end
end

local function showTranscribingIndicator()
    hideRecordingIndicator()
    local screen = hs.screen.mainScreen():frame()
    local w, h = 240, 48
    local frame = {
        x = screen.x + (screen.w - w) / 2,
        y = screen.y + 8,
        w = w, h = h,
    }
    recordingIndicator = hs.canvas.new(frame)
    recordingIndicator:appendElements(
        {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0.15, green = 0.35, blue = 0.85, alpha = 0.95 },
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
        },
        {
            type = "text",
            text = "⋯  Transcribing…",
            textSize = 16,
            textColor = { white = 1, alpha = 1 },
            textFont = ".AppleSystemUIFont-Bold",
            textAlignment = "center",
            frame = { x = 0, y = 12, w = w, h = h - 20 },
        }
    )
    recordingIndicator:behavior({ "canJoinAllSpaces", "stationary" })
    recordingIndicator:level("overlay")
    recordingIndicator:show()
end

-- sox takes ~300ms to initialize audio capture on macOS. Spawning it
-- immediately but delaying the user-facing "recording" signal ensures the
-- first word isn't lost — by the time user hears the Pop and sees the
-- banner, sox is already capturing audio.
local SOX_WARMUP_MS = 400

local function startRecording()
    if state ~= "idle" then return end

    -- Capture the app that was frontmost when user started dictating
    targetApp = hs.application.frontmostApplication()
    targetAppName = targetApp and targetApp:name() or nil

    if PAUSE_MEDIA and isMediaPlaying() then
        wasMediaPlaying = true
        sendPlayPause()
    else
        wasMediaPlaying = false
    end

    -- Spawn sox immediately so it can warm up while we give user feedback
    os.remove(AUDIO_FILE)
    recordingTask = hs.task.new(SOX_BIN, nil, {
        "-d",
        "-c", "1",
        "-r", "16000",
        "-b", "16",
        AUDIO_FILE,
    })
    recordingTask:start()
    state = "recording"
    updateMenubar()

    -- Show user-facing signals AFTER sox has had time to warm up,
    -- so speaking aligns with actual capture starting.
    hs.timer.doAfter(SOX_WARMUP_MS / 1000, function()
        if state == "recording" then
            hs.sound.getByFile(SOUND_START):play()
            showRecordingIndicator()
        end
    end)
end

local function stopAndTranscribe()
    if state ~= "recording" then return end

    if recordingTask then
        recordingTask:terminate()
        recordingTask = nil
    end
    state = "transcribing"
    updateMenubar()
    hs.sound.getByFile(SOUND_STOP):play()
    showTranscribingIndicator()

    hs.timer.doAfter(0.4, function()
        local attrs = hs.fs.attributes(AUDIO_FILE)
        if not attrs or attrs.size < 2000 then
            state = "idle"
            updateMenubar()
            hs.alert.closeAll()
            flash("No audio", { red = 0.5, green = 0.5, blue = 0.5, alpha = 0.9 }, 1.2)
            hs.sound.getByFile(SOUND_ERROR):play()
            if wasMediaPlaying then sendPlayPause() end
            return
        end

        local function dlog(msg)
            if not DEBUG then return end
            local f = io.open("/tmp/hammerspoon-dictation.log", "a")
            if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
        end
        dlog("=== stopAndTranscribe begin ===")
        dlog("Audio file size: " .. (attrs and attrs.size or "nil"))

        -- Send to whisper-server (always-loaded daemon — no model reload per request)
        local PROMPT = "این یک مکالمه فارسی درباره استارتاپ، برنامه‌نویسی، بازاریابی و محصولات دیجیتال است."
        dlog("POST to whisper-server")

        local startTime = hs.timer.secondsSinceEpoch()
        hs.task.new("/usr/bin/curl", function(exitCode, stdOut, stdErr)
            local elapsed = hs.timer.secondsSinceEpoch() - startTime
            dlog(string.format("Curl exit=%d elapsed=%.2fs stdOut len=%d", exitCode, elapsed, stdOut and #stdOut or 0))

            state = "idle"
            updateMenubar()

            if wasMediaPlaying then sendPlayPause() end

            if exitCode ~= 0 or not stdOut or stdOut == "" then
                hideRecordingIndicator()
                flash("✗ Server error (exit " .. tostring(exitCode) .. ")", { red = 0.7, green = 0.1, blue = 0.1, alpha = 0.9 }, 2)
                hs.sound.getByFile(SOUND_ERROR):play()
                return
            end

            local text = stdOut:gsub("^%s+", ""):gsub("%s+$", "")
            text = applyCorrections(text)
            dlog("Cleaned text: [" .. text .. "]")

            if text == "" then
                flash("Empty transcript", { red = 0.5, green = 0.5, blue = 0.5, alpha = 0.9 }, 1.5)
                hs.sound.getByFile(SOUND_ERROR):play()
                return
            end

            hideRecordingIndicator()
            hs.pasteboard.setContents(text)

            -- Reactivate target app if focus was lost
            if targetApp then targetApp:activate(true) end

            -- Type text directly via keyStrokes (works reliably across all apps)
            hs.eventtap.keyStrokes(text)
            hs.sound.getByFile(SOUND_DONE):play()
            flash("✓ " .. text:sub(1, 50), { red = 0.15, green = 0.55, blue = 0.3, alpha = 0.9 }, 1.2)
            dlog("Done.")
        end, {
            "-s",
            "-X", "POST",
            WHISPER_SERVER,
            "-F", "file=@" .. AUDIO_FILE,
            "-F", "language=" .. LANGUAGE,
            "-F", "response_format=text",
            "-F", "temperature=0",
            "-F", "initial_prompt=" .. PROMPT,
        }):start()
    end)
end

-- ============================================================
-- Right Command tap detection (minimal work in callbacks to avoid tap timeout)
-- keyCode 54 = Right Command, 55 = Left Command
-- ============================================================
local rightCmdWatcher
local keyWatcher

rightCmdWatcher = hs.eventtap.new({
    hs.eventtap.event.types.flagsChanged,
}, function(event)
    if event:getKeyCode() ~= 54 then return false end
    local flags = event:getFlags()
    if flags.cmd then
        rightCmdDownTime = hs.timer.secondsSinceEpoch()
        otherKeyPressed = false
    else
        local duration = hs.timer.secondsSinceEpoch() - rightCmdDownTime
        if not otherKeyPressed and duration < TAP_MAX_DURATION then
            if state == "recording" then
                stopAndTranscribe()
            elseif state == "idle" then
                startRecording()
            end
        end
    end
    return false
end)

keyWatcher = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
}, function(event)
    if rightCmdDownTime > 0 and hs.timer.secondsSinceEpoch() - rightCmdDownTime < TAP_MAX_DURATION then
        otherKeyPressed = true
    end
    return false
end)

-- Watchdog: re-enable event taps if macOS disables them (happens if a callback
-- takes too long; safer to always restart if keyStrokes is running in parallel)
local function ensureTapsAlive()
    if rightCmdWatcher and not rightCmdWatcher:isEnabled() then
        rightCmdWatcher:start()
    end
    if keyWatcher and not keyWatcher:isEnabled() then
        keyWatcher:start()
    end
end

rightCmdWatcher:start()
keyWatcher:start()

-- Re-check every 2 seconds in case macOS disabled them
hs.timer.doEvery(2, ensureTapsAlive)

-- Listen for kCGEventTapDisabledByTimeout events and instantly re-enable
-- (rather than waiting up to 2 sec for the watchdog)
hs.eventtap.new({
    22, -- kCGEventTapDisabledByTimeout
    23, -- kCGEventTapDisabledByUserInput
}, function(event)
    if rightCmdWatcher then rightCmdWatcher:start() end
    if keyWatcher then keyWatcher:start() end
    return false
end):start()
updateMenubar()
flash("Voice dictation ready", { red = 0.15, green = 0.35, blue = 0.65, alpha = 0.9 }, 1.5)
