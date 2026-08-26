require "yaml"

module ObsSceneCtlr
  class ConfigError < StandardError; end

  # Loads and validates config/config.yml, exposing OBS connection settings,
  # the main camera scene, commercial duration, and the configured playlists.
  class Config
    DEFAULT_PATH = File.expand_path("../../config/config.yml", __dir__)
    DEFAULT_ROOT_DIR = File.expand_path("../..", __dir__)

    attr_reader :obs_host, :obs_port, :obs_password, :main_scene,
                :commercial_duration, :playlists, :root_dir, :source_path

    def self.load(path = DEFAULT_PATH, root_dir: DEFAULT_ROOT_DIR)
      raise ConfigError, "Config file not found: #{path}" unless File.exist?(path)

      data = YAML.safe_load(File.read(path)) || {}
      new(data, root_dir: root_dir, source_path: path)
    end

    def initialize(data, root_dir: DEFAULT_ROOT_DIR, source_path: nil)
      @root_dir = root_dir
      @source_path = source_path || DEFAULT_PATH

      obs = data["obs"] || {}
      @obs_host = obs.fetch("host") { raise ConfigError, "obs.host is required in config" }
      @obs_port = obs.fetch("port") { raise ConfigError, "obs.port is required in config" }
      @obs_password = obs["password"]

      @main_scene = data.fetch("main_scene") { raise ConfigError, "main_scene is required in config" }
      @commercial_duration = data.fetch("commercial_duration") { raise ConfigError, "commercial_duration is required in config" }

      @playlists = data.fetch("playlists") { raise ConfigError, "playlists is required in config" }
      if @playlists.nil? || @playlists.empty?
        raise ConfigError, "playlists must define at least one playlist"
      end

      @playlists.each do |name, scenes|
        unless scenes.is_a?(Array) && !scenes.empty?
          raise ConfigError, "playlist '#{name}' must be a non-empty list of scene names"
        end
      end
    end

    def playlist_names
      playlists.keys
    end

    def playlist?(name)
      playlists.key?(name)
    end

    def scenes_for(playlist_name)
      playlists.fetch(playlist_name) do
        raise ConfigError, "Unknown playlist '#{playlist_name}'. Known playlists: #{playlist_names.join(', ')}"
      end
    end

    def state_dir
      File.join(root_dir, "state")
    end

    def run_dir
      File.join(root_dir, "run")
    end
  end
end
