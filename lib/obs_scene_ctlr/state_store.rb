require "json"
require "fileutils"
require "time"

module ObsSceneCtlr
  # Tracks rotation position for a single playlist in state/<playlist>.json.
  # last_played_index starts at -1 (nothing played yet) so index 0 is next.
  class StateStore
    attr_reader :path, :playlist_name

    def initialize(playlist_name, state_dir:)
      @playlist_name = playlist_name
      @state_dir = state_dir
      @path = File.join(@state_dir, "#{playlist_name}.json")
      load_or_create
    end

    def last_played_index
      @data["last_played_index"]
    end

    def last_played_scene
      @data["last_played_scene"]
    end

    def next_index(scene_count)
      (last_played_index + 1) % scene_count
    end

    # Persists a successful scene switch. Callers must only invoke this
    # after OBS has confirmed the switch, never before.
    def record_play!(index, scene_name)
      @data = {
        "last_played_index" => index,
        "last_played_scene" => scene_name,
        "updated_at" => Time.now.utc.iso8601
      }
      persist!
    end

    def reset!
      @data = default_data
      persist!
    end

    private

    def load_or_create
      FileUtils.mkdir_p(@state_dir)
      if File.exist?(@path)
        begin
          @data = JSON.parse(File.read(@path))
        rescue JSON::ParserError
          @data = default_data
        end
      else
        @data = default_data
        persist!
      end
    end

    def default_data
      { "last_played_index" => -1, "last_played_scene" => nil, "updated_at" => nil }
    end

    def persist!
      FileUtils.mkdir_p(@state_dir)
      tmp_path = "#{@path}.tmp"
      File.write(tmp_path, JSON.pretty_generate(@data))
      File.rename(tmp_path, @path)
    end
  end
end
