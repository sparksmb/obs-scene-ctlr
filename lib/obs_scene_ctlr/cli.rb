require "yaml"
require_relative "config"
require_relative "state_store"
require_relative "run_lock"
require_relative "control_flag"
require_relative "obs_client"
require_relative "runner"

module ObsSceneCtlr
  class CLI
    DEFAULT_PLAYLIST = "main"
    INTEGER_PATTERN = /\A\d+\z/
    MAIN_CAMERA_SCENE_NAME = "Camera Scene"

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv
      @out = out
      @err = err
    end

    # Returns a process exit code.
    def run
      command = @argv[0]
      playlist_name = @argv[1] || DEFAULT_PLAYLIST

      if command.nil? || command.empty?
        usage
        return 1
      end

      config = Config.load
      if command != "populate" && !config.playlist?(playlist_name)
        @err.puts "Unknown playlist '#{playlist_name}'. Known playlists: #{config.playlist_names.join(', ')}"
        return 1
      end

      run_lock = RunLock.new(run_dir: config.run_dir)
      control_flag = ControlFlag.new(run_dir: config.run_dir)
      obs_client = ObsClient.new(host: config.obs_host, port: config.obs_port, password: config.obs_password)

      dispatch(command, playlist_name, config, run_lock, control_flag, obs_client)
    rescue ConfigError => e
      @err.puts "Config error: #{e.message}"
      1
    end

    private

    def dispatch(command, playlist_name, config, run_lock, control_flag, obs_client)
      if command.match?(INTEGER_PATTERN)
        cmd_run(config, obs_client, run_lock, control_flag, playlist_name, Integer(command))
      else
        case command
        when "loop"
          cmd_run(config, obs_client, run_lock, control_flag, playlist_name, nil)
        when "stop"
          cmd_stop(run_lock, control_flag)
        when "abort"
          cmd_abort(config, obs_client, run_lock, control_flag)
        when "reset"
          cmd_reset(config, run_lock, playlist_name)
        when "status"
          cmd_status(config, run_lock)
        when "populate"
          cmd_populate(config, obs_client, run_lock, playlist_name)
        else
          usage
          1
        end
      end
    end

    def cmd_run(config, obs_client, run_lock, control_flag, playlist_name, count)
      if count && count <= 0
        @err.puts "<integer> must be a positive whole number"
        return 1
      end

      success = Runner.new(
        config: config,
        obs_client: obs_client,
        run_lock: run_lock,
        control_flag: control_flag,
        playlist_name: playlist_name,
        count: count,
        out: @out
      ).call

      success ? 0 : 1
    end

    def cmd_stop(run_lock, control_flag)
      holder = run_lock.current_holder
      if holder.nil?
        @out.puts "No run in progress."
        return 0
      end

      control_flag.request_stop!
      @out.puts "Stop requested; current commercial will finish, then return to MAIN CAMERA " \
                 "(playlist=#{holder['playlist']}, pid=#{holder['pid']})."
      0
    end

    def cmd_abort(config, obs_client, run_lock, control_flag)
      holder = run_lock.current_holder
      control_flag.request_abort! if holder

      begin
        obs_client.switch_scene(config.main_scene)
      rescue ObsConnectionError => e
        @err.puts "ERROR: #{e.message}"
        return 1
      end

      @out.puts "Aborted. Switched to '#{config.main_scene}'."
      0
    end

    def cmd_reset(config, run_lock, playlist_name)
      if run_lock.current_holder
        @err.puts "Cannot reset while a run is active. Use `stop` or `abort` first."
        return 1
      end

      state = StateStore.new(playlist_name, state_dir: config.state_dir)
      state.reset!
      @out.puts "Rotation for playlist '#{playlist_name}' reset; next commercial is " \
                "'#{config.scenes_for(playlist_name).first}'."
      0
    end

    def cmd_populate(config, obs_client, run_lock, playlist_name)
      if run_lock.current_holder
        @err.puts "Cannot populate while a run is active. Use `stop` or `abort` first."
        return 1
      end

      begin
        scene_names = obs_client.list_scene_names
      rescue ObsConnectionError => e
        @err.puts "ERROR: #{e.message}"
        return 1
      end

      unless scene_names.include?(MAIN_CAMERA_SCENE_NAME)
        @err.puts "OBS has no scene named '#{MAIN_CAMERA_SCENE_NAME}'. No changes made to config.yml."
        return 1
      end

      commercial_scenes = scene_names.reject { |name| name == MAIN_CAMERA_SCENE_NAME }
      if commercial_scenes.empty?
        @err.puts "No scenes found in OBS besides '#{MAIN_CAMERA_SCENE_NAME}'. No changes made to config.yml."
        return 1
      end

      raw = YAML.safe_load(File.read(config.source_path)) || {}
      raw["main_scene"] = MAIN_CAMERA_SCENE_NAME
      raw["playlists"] ||= {}
      raw["playlists"][playlist_name] = commercial_scenes
      File.write(config.source_path, YAML.dump(raw))

      @out.puts "Populated playlist '#{playlist_name}' with #{commercial_scenes.length} scene(s); " \
                "main_scene set to '#{MAIN_CAMERA_SCENE_NAME}'."
      commercial_scenes.each { |name| @out.puts "  - #{name}" }
      0
    end

    def cmd_status(config, run_lock)
      holder = run_lock.current_holder
      if holder
        @out.puts "ACTIVE: mode=#{holder['mode']} playlist=#{holder['playlist']} pid=#{holder['pid']} " \
                   "count=#{holder['count'] || 'n/a'} started_at=#{holder['started_at']}"
      else
        @out.puts "IDLE: no run in progress."
      end

      config.playlist_names.each do |name|
        scenes = config.scenes_for(name)
        state = StateStore.new(name, state_dir: config.state_dir)
        next_scene = scenes[state.next_index(scenes.length)]
        @out.puts "  [#{name}] last_played=#{state.last_played_scene || 'none'} next_up=#{next_scene}"
      end
      0
    end

    def usage
      @err.puts <<~USAGE
        Usage: run.rb <command> [playlist]
          <integer>   Play the next N commercials (default playlist: #{DEFAULT_PLAYLIST})
          loop        Loop commercials until stop/abort
          stop        Gracefully stop after the current commercial finishes
          abort       Immediately cut to the main camera scene
          reset       Reset a playlist's rotation to the first commercial
          status      Show active run and per-playlist rotation status
          populate    Read OBS's live scene list and (re)write it into config.yml
      USAGE
    end
  end
end
