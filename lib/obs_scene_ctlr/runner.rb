require "time"
require_relative "state_store"
require_relative "obs_client"

module ObsSceneCtlr
  # Orchestrates a single run: acquires the global lock, plays commercials
  # from a playlist (bounded to `count`, or indefinitely when count is nil),
  # persisting rotation state after each successful OBS scene switch, and
  # polling the control flag so `stop`/`abort` can interrupt promptly.
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
        break if @count && played >= @count

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

        break if @count && played >= @count

        wait_result = poll_wait(@config.commercial_duration)
        if wait_result == :abort
          aborted = true
          break
        elsif wait_result == :stop
          break
        end
      end

      return_to_main_scene unless aborted
      true
    end

    def return_to_main_scene
      @obs_client.switch_scene(@config.main_scene)
    rescue ObsConnectionError => e
      @out.puts "ERROR returning to main scene: #{e.message}"
    end

    # Sleeps for `seconds`, checking the control flag every POLL_INTERVAL so
    # stop/abort are noticed promptly. Returns :abort, :stop, or :completed.
    def poll_wait(seconds)
      elapsed = 0.0
      while elapsed < seconds
        action = @control_flag.requested
        return action.to_sym if action

        step = [POLL_INTERVAL, seconds - elapsed].min
        sleep(step)
        elapsed += step
      end
      :completed
    end
  end
end
