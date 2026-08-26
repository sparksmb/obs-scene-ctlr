# OBS Scene Controller

A Ruby command-line controller for running a sponsor commercial rotation in
OBS via [obs-websocket](https://github.com/obsproject/obs-websocket) (v5,
built into OBS 28+), designed to be triggered from Stream Deck buttons.

It rotates through a configured list of OBS scenes, waits for each
commercial's actual media playback to finish (not a guessed fixed length),
and switches back to your main camera scene automatically.

## Requirements

- Ruby (managed via `asdf`; see `.tool-versions`) with gems installed via
  `bundle install`
- OBS Studio with the WebSocket server enabled (Tools → WebSocket Server
  Settings), with the host/port/password filled into `config/config.yml`

## Setup

```bash
bundle install
```

Edit `config/config.yml`:

```yaml
obs:
  host: 192.168.4.40      # IP/hostname of the machine running OBS
  port: 4455
  password: "..."          # from OBS's WebSocket Server Settings dialog

main_scene: Camera Scene   # exact OBS scene name to return to between/after commercials

# Safety-net ceiling only (seconds). The controller detects each commercial's
# actual end via OBS media status; this is just the max time to wait before
# giving up and moving on regardless (e.g. if a media source loops, or
# detection otherwise fails).
max_commercial_duration: 120

playlists:
  main:
    - FirstBaptist
    - McDonald
    - Whataburger
    - CLife

# Optional: only needed for a scene with more than one Media/VLC source,
# where auto-detection (by input kind) would be ambiguous about which one
# to watch for end-of-playback. Uncomment and set the exact source name.
#media_sources:
#   McDonald: "McDonaldAd"
```

Each commercial scene should contain a Media Source (or VLC Video Source)
whose OBS name doesn't need to match the scene name — the controller
auto-detects it (or use `media_sources` above to be explicit).

You can auto-populate `playlists` from OBS's current scene list instead of
typing it by hand — see `populate` below. It requires a scene literally
named `Camera Scene` to exist in OBS.

## Commands

All commands are run as:

```bash
ruby bin/run.rb <command> [playlist]
```

`playlist` defaults to `main` if omitted.

- **`<integer>`** — play the next N commercials in rotation order, then
  return to `main_scene`. e.g. `ruby bin/run.rb 1` plays exactly one.
- **`loop`** — play commercials continuously until `stop` or `abort`.
- **`stop`** — request a graceful stop. The commercial currently playing
  finishes naturally (its real end is still detected), then it returns to
  `main_scene`. Only takes effect between commercials — it never cuts one
  short.
- **`abort`** — cut to `main_scene` immediately, even mid-commercial. Works
  even if a `loop`/`<integer>` run is stuck or OBS is misbehaving.
- **`reset`** — reset a playlist's rotation so the next commercial played is
  the first one in its list again.
- **`status`** — show whether a run is active (mode, pid, playlist) and,
  for every configured playlist, the last commercial played and what's
  next up.
- **`populate [playlist]`** — read OBS's live scene list and rewrite
  `config.yml`: sets `main_scene` to `Camera Scene` and the given
  playlist (default `main`) to every other scene OBS reports. Overwrites
  the existing playlist entry. Typically run once during setup/rehearsal,
  not during the live show. Fails without changing anything if OBS has no
  scene literally named `Camera Scene`.

Only one `<integer>`/`loop` run can be active system-wide at a time; a
second attempt will refuse to start and tell you who's running.

### Testing without OBS

Set `OBS_DRY_RUN=1` to exercise any command without a real OBS connection —
it logs what it *would* do instead of making WebSocket calls:

```bash
OBS_DRY_RUN=1 ruby bin/run.rb status
```

## Stream Deck setup

Each command has a matching wrapper script in the repo root:

| Script | Command |
| --- | --- |
| `next.sh` | play one commercial |
| `loop.sh` | start continuous rotation |
| `stop.sh` | graceful stop |
| `abort.sh` | emergency cut to camera |
| `reset.sh` | reset rotation |
| `status.sh` | print status |
| `populate.sh` | refresh playlist from OBS |
| `tail_log.sh` | live-tail the log (see Monitoring below) |

These wrappers exist because Stream Deck's **System → Open** action launches
programs without sourcing your shell's `.zshrc`/`.zprofile`. Without that,
plain `ruby` on PATH resolves to macOS's built-in system Ruby instead of the
`asdf`-managed one with this project's gems installed, and commands fail
with `cannot load such file -- obsws`. Each script explicitly sets `PATH` to
include Homebrew and `asdf` before running, so it works regardless of what
environment Stream Deck provides.

To wire up a button:

1. In the Stream Deck app, add a **System → Open** action to a button.
2. Set **App / File** to the absolute path of the script, e.g.
   `/Users/sparks/source/obs-scene-ctlr/loop.sh`.
3. Repeat for each button you want (Next Ad, Pregame Loop, Stop, Abort,
   etc.), pointing at the matching script.
4. Press the button and check `tail_log.sh` (below) to confirm it worked —
   Stream Deck won't show you any output itself.

If you add new scripts of your own, copy the `PATH`/`cd`/`exec` pattern from
an existing one (e.g. `stop.sh`) so they work the same way.

## Monitoring

Since Stream Deck buttons run in the background with no visible terminal,
`run.rb` mirrors everything it prints to `logs/controller.log` (in addition
to STDOUT), timestamped, regardless of how it was invoked.

Keep a terminal window open during the broadcast running:

```bash
./tail_log.sh
```

This creates the log file if it doesn't exist yet and live-tails it, so you
can watch every button press, scene switch, and warning as it happens.

## Troubleshooting

- **`cannot load such file -- obsws`** — a script is invoking the wrong
  Ruby (see Stream Deck setup above). Confirm the failing script has the
  `PATH=...` line at the top, matching the others.
- **A commercial gets cut off far short of its real length** — its media
  source may have OBS's "Restart playback when source becomes active" left
  in an inconsistent state, or you have two Media/VLC sources in that scene
  and the wrong one is being watched; set an explicit override in
  `media_sources` (see Setup above).
- **A commercial plays for the full `max_commercial_duration` every time
  instead of its real length** — check for a `WARNING: ... did not report
  ended` line in the log. This usually means the source has **Loop**
  enabled in OBS (so it never reports "ended"), or no media source could be
  detected in that scene at all.
- **`A run is already in progress...`** — a `loop`/`<integer>` run is
  already active; use `stop.sh` or `abort.sh` first, or check `status.sh`.
