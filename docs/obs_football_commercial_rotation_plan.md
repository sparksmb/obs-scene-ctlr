# OBS Football Commercial Rotation Controller Plan

## Goal

Build a reliable commercial-control system for the football broadcast
that:

-   Plays at least six 30-second commercial scenes in a fair round-robin
    rotation.
-   Remembers the last commercial played so the next commercial is
    always next in sequence.
-   Supports continuous commercial loops before the game and during
    halftime.
-   Allows the operator to stop a loop gracefully after the current
    commercial.
-   Allows an immediate emergency cut back to the main camera.
-   Can later support different playlists, non-commercial promos,
    unequal commercial lengths, and impression tracking.
-   Uses the Stream Deck as the operator interface.
-   Uses **Ruby** for the controller logic.

## Recommended Architecture

``` text
Stream Deck
    |
    v
Ruby Commercial Controller
    |
    +-- Persistent Rotation State
    |
    +-- Playlist / Mode Logic
    |
    v
OBS WebSocket
    |
    v
OBS Scenes + Media Sources
```

### Responsibility of Each Layer

**OBS** - Stores the Main Camera scene and individual commercial
scenes. - Plays the commercial video. - Restarts each commercial when
its scene becomes active. - Continues to handle the actual broadcast
output.

**Ruby controller** - Decides which commercial plays next. - Keeps track
of the last commercial played. - Starts and stops automated commercial
loops. - Controls transitions back to the Main Camera. - Maintains
sponsor fairness across all commercial breaks.

**Stream Deck** - Provides simple operator buttons. - Launches Ruby
commands. - Does not need to contain the commercial rotation logic
itself.

------------------------------------------------------------------------

## OBS Scene Structure

Keep individual scenes for each commercial.

Example:

``` text
MAIN CAMERA

COMM - 01 - Sponsor A
COMM - 02 - Sponsor B
COMM - 03 - Sponsor C
COMM - 04 - Sponsor D
COMM - 05 - Sponsor E
COMM - 06 - Sponsor F
```

Each commercial scene should contain its corresponding Media Source.

For each commercial Media Source, enable:

> Restart playback when source becomes active

This allows the Ruby controller to start a commercial simply by
switching OBS to that scene.

------------------------------------------------------------------------

## Master Sponsor Rotation

The controller should maintain one master sponsor rotation.

Example Ruby configuration:

``` ruby
COMMERCIALS = [
  "COMM - 01 - Sponsor A",
  "COMM - 02 - Sponsor B",
  "COMM - 03 - Sponsor C",
  "COMM - 04 - Sponsor D",
  "COMM - 05 - Sponsor E",
  "COMM - 06 - Sponsor F"
]
```

The sequence is always:

``` text
1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 1 -> 2...
```

The rotation should be shared by every commercial mode.

For example, if pregame ends after Sponsor C, the first commercial
during the game should be Sponsor D.

This prevents every commercial block from beginning with Sponsor A and
keeps sponsor exposure approximately equal.

------------------------------------------------------------------------

## Persistent State

Store the current rotation position in a small local state file.

For example:

``` text
~/broadcast/commercials/state.json
```

Possible contents:

``` json
{
  "last_commercial": 3
}
```

The controller reads this file before selecting the next commercial and
updates it immediately when a commercial is played.

Persistent state means the rotation survives:

-   Stopping a commercial loop
-   Restarting the Ruby controller
-   Closing Stream Deck
-   Restarting OBS
-   Rebooting the Mac

------------------------------------------------------------------------

## Initial Stream Deck Controls

### NEXT AD

Plays exactly one commercial.

``` text
Determine next sponsor
        |
        v
Switch OBS to commercial scene
        |
        v
Play commercial
        |
        v
Update rotation state
        |
        v
Return to MAIN CAMERA
```

Example Stream Deck command:

``` bash
ruby ~/broadcast/commercials/commercials.rb next
```

------------------------------------------------------------------------

### PREGAME ADS

Starts a continuous sponsor rotation.

Example:

``` text
Sponsor D
   |
30 seconds
   |
Sponsor E
   |
30 seconds
   |
Sponsor F
   |
30 seconds
   |
Sponsor A
   |
...
```

Command:

``` bash
ruby ~/broadcast/commercials/commercials.rb loop pregame
```

The rotation continues until a stop command is received.

------------------------------------------------------------------------

### HALFTIME ADS

Initially this can behave exactly like the pregame loop:

``` bash
ruby ~/broadcast/commercials/commercials.rb loop halftime
```

Keeping `pregame` and `halftime` as separate modes from the beginning
allows their playlists to become different later.

------------------------------------------------------------------------

### STOP ADS

Requests a graceful stop.

The current commercial should **finish before returning to the Main
Camera**.

Example:

``` text
Sponsor B playing
        |
Operator presses STOP ADS
        |
Sponsor B continues
        |
Commercial finishes
        |
MAIN CAMERA
```

Command:

``` bash
ruby ~/broadcast/commercials/commercials.rb stop
```

This prevents accidentally cutting off a sponsor's paid commercial.

------------------------------------------------------------------------

### CUT TO CAMERA

Emergency override.

Immediately switch OBS to:

``` text
MAIN CAMERA
```

regardless of what the commercial controller is doing.

Command:

``` bash
ruby ~/broadcast/commercials/commercials.rb abort
```

This is useful when:

-   The team unexpectedly enters the field.
-   Kickoff is about to occur.
-   The announcers need to return immediately.
-   Something important happens during halftime.
-   A commercial or automation malfunctions.

------------------------------------------------------------------------

### RESET ROTATION

Manually reset the rotation if necessary.

``` bash
ruby ~/broadcast/commercials/commercials.rb reset
```

This would make Sponsor A the next commercial.

This should probably be a less-accessible Stream Deck button because it
should rarely be needed.

------------------------------------------------------------------------

## Suggested Ruby Command Interface

Design the Ruby controller as one command-line program:

``` text
commercials.rb next
commercials.rb loop pregame
commercials.rb loop halftime
commercials.rb stop
commercials.rb abort
commercials.rb reset
commercials.rb status
```

This keeps Stream Deck configuration extremely simple.

Stream Deck only needs to execute the appropriate Ruby command.

------------------------------------------------------------------------

## Commercial Timing - Version 1

Because the current commercials are standardized at 30 seconds, Version
1 can use timing.

Conceptually:

``` ruby
switch_to(commercial_scene)

sleep 30

switch_to("MAIN CAMERA")
```

For continuous mode:

``` ruby
loop do
  commercial = next_commercial

  switch_to(commercial)

  sleep 30

  break if stop_requested?
end

switch_to("MAIN CAMERA")
```

The actual implementation should include safeguards around timing, state
changes, and multiple controller processes.

------------------------------------------------------------------------

## Commercial Timing - Future Version

Eventually, avoid assuming that every commercial is exactly 30 seconds.

Future inventory could contain:

-   15-second spots
-   30-second spots
-   60-second spots
-   School promos
-   Upcoming-game promos
-   Halftime features

The controller can eventually use OBS media playback state/events to
detect when the media actually finishes.

The logical flow becomes:

``` text
Switch to commercial
        |
        v
OBS begins media
        |
        v
Wait for media-ended event
        |
        v
Next commercial or Main Camera
```

This should be a later enhancement rather than part of Version 1.

------------------------------------------------------------------------

## Playlist Design

Keep the **sponsor rotation** separate from the **broadcast playlist**.

This will become useful when pregame and halftime include non-commercial
content.

For example:

### Pregame Playlist

``` text
Sponsor
Sponsor
School Promo
Sponsor
Sponsor
Upcoming Games
Repeat
```

### Halftime Playlist

``` text
Sponsor
Sponsor
Halftime Feature
Sponsor
Sponsor
Scoreboard / Upcoming Schedule
Repeat
```

Whenever the playlist encounters:

``` text
Sponsor
```

the controller asks the master sponsor rotation for the next sponsor.

Example:

``` text
Master rotation currently points to Sponsor D.

Pregame:
  Sponsor        -> Sponsor D
  Sponsor        -> Sponsor E
  School Promo
  Sponsor        -> Sponsor F

Pregame stops.

Game timeout:
  Sponsor        -> Sponsor A

Halftime:
  Sponsor        -> Sponsor B
  Sponsor        -> Sponsor C
```

The broadcast playlist and sponsor rotation therefore remain
independent.

------------------------------------------------------------------------

## Future Impression Tracking

A later version can maintain counts such as:

``` text
Sponsor A: 4
Sponsor B: 4
Sponsor C: 4
Sponsor D: 3
Sponsor E: 3
Sponsor F: 3
```

This could be stored in the same state file or in a broadcast-specific
log.

Possible future features:

-   Total plays per sponsor
-   Plays per game
-   Timestamp of every commercial
-   Pregame vs game vs halftime counts
-   Exportable sponsor impression report
-   Detection of accidentally repeated commercials

Round-robin rotation should be implemented first. Detailed impression
balancing can be added later if needed.

------------------------------------------------------------------------

## Suggested Directory Structure

``` text
~/broadcast/commercials/
|
+-- commercials.rb
+-- config.yml
+-- state.json
+-- stop.flag
+-- logs/
    |
    +-- 2026-08-28-football.log
```

### `commercials.rb`

Main Ruby controller.

### `config.yml`

Configuration such as:

``` yaml
main_scene: "MAIN CAMERA"

commercial_duration: 30

commercials:
  - "COMM - 01 - Sponsor A"
  - "COMM - 02 - Sponsor B"
  - "COMM - 03 - Sponsor C"
  - "COMM - 04 - Sponsor D"
  - "COMM - 05 - Sponsor E"
  - "COMM - 06 - Sponsor F"
```

This allows commercials to be added or removed without changing Ruby
code.

### `state.json`

Persistent rotation and impression state.

### `stop.flag`

One possible simple mechanism for communicating a graceful stop request
to a running loop.

The implementation may use another IPC mechanism instead if it proves
cleaner.

### `logs/`

Optional audit log of every commercial played.

------------------------------------------------------------------------

## Reliability Requirements

The controller should eventually protect against several operator and
process problems.

### Prevent Two Loops

Pressing PREGAME ADS twice should not launch two competing commercial
loops.

The controller should use a PID file, lock file, or another
process-locking mechanism.

### OBS Connection Failure

If OBS WebSocket cannot be reached:

-   Do not modify the rotation state.
-   Log the error.
-   Exit cleanly.

### State Update

Only record a commercial as played after OBS successfully switches to
the commercial scene.

### Manual OBS Scene Changes

If the operator manually changes scenes during an automated commercial
loop, the controller should eventually detect or tolerate this safely.

For Version 1, CUT TO CAMERA should be the supported way to interrupt
the automation.

### Crash Recovery

If the Ruby controller crashes, OBS should remain usable manually.

The automation layer should never make normal manual OBS operation
dependent on the controller.

------------------------------------------------------------------------

## Implementation Stages

### Stage 1 - NEXT AD

Build the smallest working controller.

Requirements:

-   Connect Ruby to OBS WebSocket.
-   Read the commercial list.
-   Read persistent rotation state.
-   Determine the next commercial.
-   Switch OBS to that scene.
-   Wait 30 seconds.
-   Return to MAIN CAMERA.
-   Save the new rotation position.
-   Launch from Stream Deck.

This validates the entire architecture.

------------------------------------------------------------------------

### Stage 2 - Continuous Loops

Add:

``` text
loop pregame
loop halftime
stop
abort
```

Requirements:

-   Continuous rotation
-   Graceful stop
-   Emergency camera cut
-   Protection against multiple simultaneous loops

At this point the system should be usable for the football broadcast.

------------------------------------------------------------------------

### Stage 3 - Playlist Support

Separate sponsor selection from playlist sequencing.

Add support for:

-   School promos
-   Upcoming game promos
-   Halftime content
-   Other station IDs or broadcast elements

Pregame and halftime can then have different content while sharing the
same sponsor rotation.

------------------------------------------------------------------------

### Stage 4 - OBS Media Events

Replace fixed 30-second waits with actual media-ended detection.

This allows commercials and promos of different lengths.

------------------------------------------------------------------------

### Stage 5 - Reporting and Advanced Rotation

Add optional commercial logging and reporting.

Possible output:

``` text
Jackrabbit Live
Football - August 28, 2026

Sponsor A     6 plays
Sponsor B     6 plays
Sponsor C     6 plays
Sponsor D     6 plays
Sponsor E     5 plays
Sponsor F     5 plays
```

This could eventually provide useful sponsor fulfillment records.

------------------------------------------------------------------------

## Recommended First Build

Start with **Stage 1: NEXT AD**.

Do not initially build playlists, reporting, media-ended event handling,
or sophisticated balancing.

The first milestone is:

> Press one Stream Deck button, have Ruby determine the correct next
> sponsor, switch OBS to that commercial, play it for 30 seconds, return
> to the Main Camera, and remember where the rotation stopped.

Once that works reliably, continuous pregame and halftime rotation are
straightforward additions.

## Final Design Principle

The Stream Deck should remain the **operator interface**, not the
automation engine.

OBS should remain the **broadcast and media engine**.

Ruby should become the **commercial decision and automation engine**.

That separation keeps the system understandable, testable, and
expandable while preserving the ability to operate OBS manually if the
automation ever fails.
