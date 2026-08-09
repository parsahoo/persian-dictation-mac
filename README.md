# Persian Voice Dictation for macOS

Free, fast, 100% local voice-to-text dictation for macOS, optimized for Persian (فارسی) but works with any language Whisper supports.

Tap **Right Command**, speak, tap again, and text is typed into the focused app — any app, anywhere. Runs entirely offline using [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

No subscription. No cloud. No telemetry. No trials.

---

## Features

- **Global hotkey**: tap Right Command to toggle recording — works in any app (browser, IDE, Slack, Notes…)
- **Near real-time**: ~2 second transcription via always-loaded `whisper-server`
- **Highest-quality Persian**: Uses `ggml-large-v3-turbo` with a Persian context prompt
- **Auto-pauses YouTube/Spotify/Music** while recording (so the mic doesn't transcribe what your speakers are playing)
- **Pulsing recording indicator** at top of screen so you never lose track of state
- **Custom vocabulary corrections** — fix recurring mishearings of your project names, brand terms, etc.
- **Auto-start at login** via LaunchAgent
- **Resilient** — event-tap watchdog reinstates hotkey if macOS disables it
- **No first-word cutoff** — sox warmup is handled before the start signal

---

## Requirements

- macOS 12+ (Apple Silicon recommended; works on Intel too)
- [Homebrew](https://brew.sh)
- ~2 GB disk space (Whisper model)
- ~1.6 GB RAM (keeps the model loaded for instant transcription)

---

## Install

```bash
git clone https://github.com/parsahoo/persian-dictation-mac.git
cd persian-dictation-mac
./install.sh
```

The installer will:
1. Install `whisper-cpp`, `sox`, `nowplaying-cli`, and Hammerspoon via Homebrew
2. Download the Whisper large-v3-turbo model (~1.5 GB) to `~/.whisper-models/`
3. Copy `init.lua` to `~/.hammerspoon/`
4. Set up a LaunchAgent to auto-start `whisper-server` at login

After install, launch Hammerspoon from `/Applications` and grant Accessibility permission when prompted.

---

## Usage

- **Start/stop recording**: tap Right Command (press and release quickly, alone)
- **Cancel**: tap Right Command again during transcription (if supported)
- **Visual**: Red "RECORDING" banner appears at top of screen. Menu bar shows `● REC` → `⋯ …` → `◌ mic`

---

## Customize

Edit `~/.hammerspoon/init.lua` to change:

| Setting | Default | Notes |
|---|---|---|
| `LANGUAGE` | `"fa"` | `"fa"` Persian, `"en"` English, `"auto"` detect |
| `PAUSE_MEDIA` | `true` | Auto-pause YouTube/Spotify/Music while recording |
| `SOX_WARMUP_MS` | `400` | Delay (ms) before start signal, so sox has time to initialize |
| `TAP_MAX_DURATION` | `0.8` | Max seconds for a "tap" vs a "hold" |
| `PROMPT` | Persian startup context | Initial context hint — improves accuracy |
| `CORRECTIONS` | VSCode, GitHub, Claude | Your custom vocabulary (see below) |

Reload after edits: click the Hammerspoon menu-bar icon → **Reload Config**.

### Adding custom vocabulary

Whisper sometimes mishears specific words (names, jargon). Add pairs of `correct -> mishearings`:

```lua
local CORRECTIONS = {
    ["MyStartup"]   = { "مای استارتاپ", "مای استارت اپ" },
    ["OpenAI"]      = { "اوپن ای", "اوپن ایه" },
    ["نیم‌فاصله"]   = { "نیم فاصله", "نیمفاصله" },
}
```

After transcription, each mishearing in the text is replaced with the correct form.

---

## Uninstall

```bash
./uninstall.sh
```

This removes the LaunchAgent and Hammerspoon config. Homebrew packages and the Whisper model are left in place (remove manually if desired — see the uninstaller output).

---

## Troubleshooting

**"No audio" every time**
- Check System Settings → Privacy & Security → Microphone → Hammerspoon is allowed

**Dictation works once then stops**
- The event-tap was disabled by macOS. The built-in watchdog should re-enable it within 2 seconds.
- If persistent: quit & relaunch Hammerspoon.

**First word is cut off**
- Increase `SOX_WARMUP_MS` in `init.lua` (try 600 or 800)

**Transcription is slow**
- Confirm the server is running: `curl http://localhost:8080/` should return HTML
- If not: `launchctl list | grep whisper-server`

**Persian words get misheard**
- Add them to `CORRECTIONS` (see above)
- Update `PROMPT` to include domain context

---

## Why These Choices (Product Decisions)

| Decision | Why |
|----------|-----|
| **100% local / offline** | Privacy is non-negotiable for dictation — you're speaking passwords, personal notes, medical info. Cloud APIs also add latency and recurring cost. Local-first removes both. |
| **Right Command as hotkey** | It's the only modifier key with zero conflicts on macOS. No app uses it alone, so it never fights shortcuts. One tap to start, one to stop — zero learning curve. |
| **Always-loaded model** | Whisper's 1.5 GB model takes 2-3 seconds to load from disk. Keeping it in RAM via a LaunchAgent daemon means transcription starts in ~100ms, not 3 seconds. The tradeoff is ~1.6 GB RAM, but modern Macs have plenty. |
| **Hammerspoon, not a native app** | Building a Swift menubar app would take weeks. Hammerspoon gives global hotkeys, UI overlays, and shell integration in ~300 lines of Lua. Ship fast, iterate later. |
| **Auto-pause media** | If Spotify is playing while you dictate, Whisper transcribes the music lyrics instead of your voice. Auto-pausing is a UX detail that prevents a confusing failure mode. |
| **Custom corrections** | Whisper consistently mishears domain-specific words (project names, brand terms). A simple find-replace table in config lets users fix this without retraining a model. |

---

## How it works

```
┌─────────────┐     press      ┌──────────────┐
│ Right Cmd   │───── tap ─────▶│ Hammerspoon  │
└─────────────┘                │  (eventtap)  │
                               └──────┬───────┘
                                      │ spawn
                                      ▼
                               ┌──────────────┐
                               │  sox -d …    │──writes to /tmp/voice-capture.wav
                               └──────────────┘
                                      │ on stop tap
                                      ▼
                               ┌──────────────────────┐
                               │  curl POST audio to  │
                               │ whisper-server:8080  │
                               └──────────┬───────────┘
                                          │ returns text
                                          ▼
                               ┌──────────────────────┐
                               │ Apply corrections +  │
                               │ hs.eventtap.keyStrokes│──> types into focused app
                               └──────────────────────┘
```

`whisper-server` keeps the 1.5 GB model loaded in RAM (managed by a LaunchAgent),
so each transcription skips the 2-3 second model-load overhead.

---

## راهنما (فارسی)

دیکته‌ی صوتی به متن، رایگان و کاملاً لوکال، برای macOS. بهینه‌شده برای فارسی.

یک بار روی **Right Command** تپ کن، حرف بزن، یک بار دیگه تپ کن، متن توی هر اپی که فوکس داری تایپ می‌شه. همه چیز آفلاین روی مک خودت اجرا می‌شه، هیچ چیز به سرور ابری نمی‌ره.

**ویژگی‌ها:**
- هات‌کی گلوبال (Right Command) در هر اپ
- ترنسکرایب حدود ۲ ثانیه (سرور whisper همیشه در حافظه لود است)
- کیفیت بالا با مدل `large-v3-turbo`
- توقف خودکار YouTube/Spotify/Music هنگام ضبط
- بنر ضبط چشمک‌زن بالای صفحه
- اصلاح واژه‌های خاص (اسم پروژه‌ها، برندها)
- خودکار هنگام بوت راه‌اندازی می‌شه
- کلمه اول قطع نمی‌شود (warmup سوکس مدیریت شده)

**نصب:**
```bash
git clone https://github.com/parsahoo/persian-dictation-mac.git
cd persian-dictation-mac
./install.sh
```

**استفاده:**
- Right Command تپ کن → حرف بزن → دوباره تپ کن → متن paste می‌شه

**شخصی‌سازی واژگان:**
اگر whisper اسم پروژه یا واژه خاصی رو اشتباه می‌شنوه، به `CORRECTIONS` داخل `~/.hammerspoon/init.lua` اضافه کن:
```lua
local CORRECTIONS = {
    ["پروژه من"] = { "پروژه منن", "پروجه من" },
}
```

---

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built on top of:
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov (MIT)
- [Hammerspoon](https://www.hammerspoon.org) (MIT)
- [nowplaying-cli](https://github.com/kirtan-shah/nowplaying-cli) (MIT)
- [sox](http://sox.sourceforge.net) (GPL)
- [OpenAI Whisper](https://github.com/openai/whisper) model weights (MIT)
