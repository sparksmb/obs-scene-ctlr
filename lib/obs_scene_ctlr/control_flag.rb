require "json"
require "fileutils"
require "time"

module ObsSceneCtlr
  # Simple file-based signal used by `stop`/`abort` to communicate with an
  # in-progress run (which polls #requested between/during commercials).
  class ControlFlag
    FILENAME = "control.flag"

    def initialize(run_dir:)
      @run_dir = run_dir
      FileUtils.mkdir_p(@run_dir)
      @path = File.join(@run_dir, FILENAME)
    end

    attr_reader :path

    def request_stop!
      write("stop")
    end

    def request_abort!
      write("abort")
    end

    # Returns "stop", "abort", or nil.
    def requested
      return nil unless File.exist?(@path)

      content = File.read(@path).strip
      return nil if content.empty?

      JSON.parse(content)["action"]
    rescue JSON::ParserError
      nil
    end

    def stop_requested?
      requested == "stop"
    end

    def abort_requested?
      requested == "abort"
    end

    def any_requested?
      !requested.nil?
    end

    def clear!
      File.delete(@path) if File.exist?(@path)
    end

    private

    def write(action)
      File.write(@path, JSON.generate("action" => action, "requested_at" => Time.now.utc.iso8601))
    end
  end
end
