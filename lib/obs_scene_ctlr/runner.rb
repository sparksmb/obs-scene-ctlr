require "time"
require_relative "state_store"
require_relative "obs_client"

module ObsSceneCtlr
  # Orchestrates a single run: acquires the global lock, plays commercials
  # from a playlist (bounded to `count`, or indefinitely when count is nil),
  # persisting rotation state after each successful OBS scene switch, and
  # waiting for each commercial's actual OBS media playback to end (falling
  # back to a fixed wait, capped at max_commercial_duration, when no media
  # source can be identified) before advancing.
  #
  # `abort` interrupts immediately, even mid-commercial. `stop` is only
  # checked between commercials, so the one currently playing always
  # finishes naturally before returning to the main scene.
  class Runner
    POLL_INTERVAL = 0.5 # seconds

    def initialize(config:, obs_client:, run_lock:, control_flag:, playlist_name:, count: nil, out: $stdout)
      @config = config
      @obs_client = obs_client
      @run_lock = run_lock
      @control_flag = control_flag
      @playlist_name = playlist_name
      @count = count
      @out = out
    end

    # Returns true if the run started and finished cleanly (including a
    # graceful stop/abort); false if it could not start, or hit an OBS
    # error before completing.
    def call
      scenes = @config.scenes_for(@playlist_name)
      state = StateStore.new(@playlist_name, state_dir: @config.state_dir)

      metadata = {
        "pid" => Process.pid,
        "mode" => @count.nil? ? "loop" : "count",
        "playlist" => @playlist_name,
        "count" => @count,
        "started_at" => Time.now.utc.iso8601
      }

      unless @run_lock.try_acquire(metadata)
        holder = @run_lock.current_holder || {}
        @out.puts "A run is already in progress (playlist=#{holder['playlist']}, mode=#{holder['mode']}, " \
                   "pid=#{holder['pid']}). Use `stop` or `abort` first."
        return false
      end

      @control_flag.clear!

      begin
        perform_run(scenes, state)
      ensure
        @control_flag.clear!
        @run_lock.release!
      end
    end

    private

    def perform_run(scenes, state)
      played = 0
      aborted = false

      loop do
        action = @control_flag.requested
        if action == "abort"
          aborted = true
          break
        elsif action == "stop"
          break
        end

        index = state.next_index(scenes.length)
        scene_name = scenes[index]

        begin
          @obs_client.switch_scene(scene_name)
        rescue ObsConnectionError => e
          @out.puts "ERROR: #{e.message}"
          return false
        end

        state.record_play!(index, scene_name)
        @out.puts "Playing #{scene_name} (#{@playlist_name})"
        played += 1

        wait_result = wait_for_commercial_to_finish(scene_name)
        if wait_result == :abort
          aborted = true
          break
        end

        break if @count && played >= @count
      end

      return_to_main_scene unless aborted
      true
    end

    def return_to_main_scene
      @obs_client.switch_scene(@config.main_scene)
    rescue ObsConnectionError => e
      @out.puts "ERROR returning to main scene: #{e.message}"
    end

    # Waits for `scene_name`'s media source to actually finish playing,
    # polling the control flag throughout so stop/abort are noticed
    # promptly. Falls back to a fixed wait (capped at max_commercial_duration)
    # when no media source can be identified. Returns :abort, :stop, or
    # :completed.
    def wait_for_commercial_to_finish(scene_name)
      input_name = detect_media_input(scene_name)
      if input_name
        restart_media_input(input_name)
        wait_for_media_ended(input_name)
      else
        @out.puts "No media source detected in '#{scene_name}'; falling back to a fixed " \
                   "#{@config.max_commercial_duration}s wait."
        poll_timeout(@config.max_commercial_duration)
      end
    end

    # Prefers an explicit config.yml media_sources override for this scene;
    # falls back to auto-detecting by input kind when none is configured.
    def detect_media_input(scene_name)
      override = @config.media_source_override(scene_name)
      return override if override

      @obs_client.scene_media_input(scene_name)
    rescue ObsConnectionError => e
      @out.puts "WARNING: could not inspect '#{scene_name}' for a media source (#{e.message}); " \
                 "falling back to a fixed-duration wait."
      nil
    end

    # Forces the media input to start playing from the beginning, so
    # end-of-playback detection tracks this play-through rather than a
    # stale state left over from a previous run.
    def restart_media_input(input_name)
      @obs_client.restart_media_input(input_name)
    rescue ObsConnectionError => e
      @out.puts "WARNING: could not restart media input '#{input_name}' (#{e.message}); " \
                 "it may report a stale ended state."
    end

    # Polls media_ended? every POLL_INTERVAL until it reports true, an
    # abort is requested, or max_commercial_duration elapses (safety net in
    # case detection fails or the source is set to loop). A pending `stop`
    # is intentionally NOT honored here: stop must let the current
    # commercial finish naturally and is only acted on between commercials
    # (see perform_run's top-of-loop check). Only `abort` interrupts mid-wait.
    def wait_for_media_ended(input_name)
      elapsed = 0.0
      max_duration = @config.max_commercial_duration

      loop do
        return :abort if @control_flag.abort_requested?

        ended = begin
          @obs_client.media_ended?(input_name)
        rescue ObsConnectionError => e
          @out.puts "WARNING: could not check media status for '#{input_name}' (#{e.message}); " \
                     "falling back to a fixed-duration wait for the remainder."
          return poll_timeout(max_duration - elapsed)
        end
        return :completed if ended

        if elapsed >= max_duration
          @out.puts "WARNING: '#{input_name}' did not report ended within #{max_duration}s; moving on anyway."
          return :completed
        end

        step = [POLL_INTERVAL, max_duration - elapsed].min
        sleep(step)
        elapsed += step
      end
    end

    # Sleeps for `seconds`, checking for `abort` every POLL_INTERVAL so it's
    # noticed promptly. Like wait_for_media_ended, a pending `stop` is not
    # honored here on purpose. Returns :abort or :completed.
    def poll_timeout(seconds)
      elapsed = 0.0
      while elapsed < seconds
        return :abort if @control_flag.abort_requested?

        step = [POLL_INTERVAL, seconds - elapsed].min
        sleep(step)
        elapsed += step
      end
      :completed
    end
  end
end
