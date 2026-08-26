require "yaml"

module ObsSceneCtlr
  class ConfigError < StandardError; end

  # Loads and validates config/config.yml, exposing OBS connection settings,
  # the main camera scene, the safety-net max commercial duration, and the
  # configured playlists.
  class Config
    DEFAULT_PATH = File.expand_path("../../config/config.yml", __dir__)
    DEFAULT_ROOT_DIR = File.expand_path("../..", __dir__)

    attr_reader :obs_host, :obs_port, :obs_password, :main_scene,
                :max_commercial_duration, :playlists, :root_dir, :source_path,
                :media_sources

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
      @max_commercial_duration = data.fetch("max_commercial_duration") { raise ConfigError, "max_commercial_duration is required in config" }

      @playlists = data.fetch("playlists") { raise ConfigError, "playlists is required in config" }
      if @playlists.nil? || @playlists.empty?
        raise ConfigError, "playlists must define at least one playlist"
      end

      @playlists.each do |name, scenes|
        unless scenes.is_a?(Array) && !scenes.empty?
          raise ConfigError, "playlist '#{name}' must be a non-empty list of scene names"
        end
      end

      @media_sources = data["media_sources"] || {}
      unless @media_sources.is_a?(Hash)
        raise ConfigError, "media_sources must be a mapping of scene name to source name"
      end

      @media_sources.each do |scene_name, source_name|
        unless source_name.is_a?(String) && !source_name.empty?
          raise ConfigError, "media_sources['#{scene_name}'] must be a non-empty source name"
        end
      end
    end

    # Returns the explicitly configured media source name for `scene_name`,
    # or nil if none was configured (in which case the caller should fall
    # back to auto-detecting the scene's media source by input kind).
    def media_source_override(scene_name)
      media_sources[scene_name]
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
