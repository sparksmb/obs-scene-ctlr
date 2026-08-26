module ObsSceneCtlr
  class ObsConnectionError < StandardError; end

  # Thin wrapper around the `obsws` gem (OBS WebSocket v5 protocol).
  # Each call opens a fresh connection, issues one request, and closes it,
  # keeping the controller resilient to OBS restarting between commercials.
  #
  # Set OBS_DRY_RUN=1 to skip real network calls entirely and just log the
  # intended scene switch, useful for exercising the CLI without live OBS.
  class ObsClient
    def initialize(host:, port:, password:, dry_run: ENV["OBS_DRY_RUN"] == "1")
      @host = host
      @port = port
      @password = password
      @dry_run = dry_run
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
  end
end
