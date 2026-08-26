module ObsSceneCtlr
  class ObsConnectionError < StandardError; end

  # Thin wrapper around the `obsws` gem (OBS WebSocket v5 protocol).
  # Each call opens a fresh connection, issues one request, and closes it,
  # keeping the controller resilient to OBS restarting between commercials.
  #
  # Set OBS_DRY_RUN=1 to skip real network calls entirely and just log the
  # intended scene switch, useful for exercising the CLI without live OBS.
  class ObsClient
    # OBS input kinds that represent playable media, used to identify which
    # scene item in a scene should be watched for end-of-playback.
    MEDIA_INPUT_KINDS = ["ffmpeg_source", "vlc_source"].freeze
    ENDED_MEDIA_STATE = "OBS_MEDIA_STATE_ENDED"

    def initialize(host:, port:, password:, dry_run: ENV["OBS_DRY_RUN"] == "1")
      @host = host
      @port = port
      @password = password
      @dry_run = dry_run
      @dry_run_media_polls = Hash.new(0)
    end

    def dry_run?
      @dry_run
    end

    def switch_scene(scene_name)
      if dry_run?
        warn "[dry-run] would switch OBS to scene '#{scene_name}'"
        return true
      end

      require "obsws"
      OBSWS::Requests::Client
        .new(host: @host, port: @port, password: @password)
        .run { |client| client.set_current_program_scene(scene_name) }
      true
    rescue StandardError => e
      raise ObsConnectionError, "Failed to switch OBS to scene '#{scene_name}': #{e.message}"
    end

    # Returns the list of scene names currently configured in OBS, in the
    # order OBS's GetSceneList reports them (note: obs-websocket v5 reports
    # scenes bottom-to-top relative to the OBS UI).
    def list_scene_names
      if dry_run?
        warn "[dry-run] returning a sample scene list instead of querying OBS"
        return ["Camera Scene", "COMM - 01 - Sponsor A", "COMM - 02 - Sponsor B", "COMM - 03 - Sponsor C"]
      end

      require "obsws"
      scenes = nil
      OBSWS::Requests::Client
        .new(host: @host, port: @port, password: @password)
        .run { |client| scenes = client.get_scene_list.scenes }
      scenes.map { |scene| scene[:sceneName] }
    rescue StandardError => e
      raise ObsConnectionError, "Failed to fetch scene list from OBS: #{e.message}"
    end

    # Returns the name of the media input (e.g. a Media Source or VLC Video
    # Source) found in the given scene, or nil if the scene has no such
    # source. Used to know which input's playback status to watch.
    def scene_media_input(scene_name)
      if dry_run?
        warn "[dry-run] assuming scene '#{scene_name}' has a media source named '#{scene_name}'"
        return scene_name
      end

      require "obsws"
      input_name = nil
      OBSWS::Requests::Client
        .new(host: @host, port: @port, password: @password)
        .run do |client|
          items = client.get_scene_item_list(scene_name).scene_items
          match = items.find { |item| MEDIA_INPUT_KINDS.include?(item[:inputKind]) }
          input_name = match[:sourceName] if match
        end
      input_name
    rescue StandardError => e
      raise ObsConnectionError, "Failed to inspect scene '#{scene_name}' for a media source: #{e.message}"
    end

    # Returns true once the given media input reports it has finished
    # playing. In dry-run mode, simulates "still playing" once and "ended"
    # from the second poll onward, so stop/abort can still be exercised.
    def media_ended?(input_name)
      if dry_run?
        @dry_run_media_polls[input_name] += 1
        ended = @dry_run_media_polls[input_name] >= 2
        warn "[dry-run] media status for '#{input_name}': #{ended ? 'ended' : 'playing'}"
        return ended
      end

      require "obsws"
      state = nil
      OBSWS::Requests::Client
        .new(host: @host, port: @port, password: @password)
        .run { |client| state = client.get_media_input_status(input_name).media_state }
      state == ENDED_MEDIA_STATE
    rescue StandardError => e
      raise ObsConnectionError, "Failed to get media status for '#{input_name}': #{e.message}"
    end

    # Forces the given media input to restart playback from the beginning.
    # Called right after switching scenes so end-of-playback detection
    # tracks a fresh play-through, regardless of whether the source's own
    # "Restart playback when source becomes active" setting is enabled (or
    # whether it was left in an "ended" state from a previous run).
    def restart_media_input(input_name)
      if dry_run?
        warn "[dry-run] would restart media input '#{input_name}'"
        @dry_run_media_polls[input_name] = 0
        return true
      end

      require "obsws"
      OBSWS::Requests::Client
        .new(host: @host, port: @port, password: @password)
        .run { |client| client.trigger_media_input_action(input_name, "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART") }
      true
    rescue StandardError => e
      raise ObsConnectionError, "Failed to restart media input '#{input_name}': #{e.message}"
    end
  end
end
