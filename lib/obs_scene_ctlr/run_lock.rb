require "json"
require "fileutils"
require "time"

module ObsSceneCtlr
  # A single, global, flock-backed lock ensuring only one <integer>/loop run
  # is active system-wide at a time, regardless of playlist.
  class RunLock
    FILENAME = "lock"

    def initialize(run_dir:)
      @run_dir = run_dir
      FileUtils.mkdir_p(@run_dir)
      @path = File.join(@run_dir, FILENAME)
      @file = nil
    end

    attr_reader :path

    # Attempts to acquire the exclusive lock and stamp it with metadata
    # (e.g. pid, mode, playlist, count, started_at). Returns true on
    # success, false if another run already holds the lock.
    def try_acquire(metadata)
      file = File.open(@path, File::CREAT | File::RDWR)
      unless file.flock(File::LOCK_EX | File::LOCK_NB)
        file.close
        return false
      end

      @file = file
      write_metadata(metadata.merge("locked_at" => Time.now.utc.iso8601))
      true
    end

    def release!
      return unless @file

      begin
        @file.truncate(0)
        @file.flock(File::LOCK_UN)
      ensure
        @file.close
        @file = nil
      end
    end

    # Reads metadata for whoever currently holds the lock, without
    # disturbing it. Returns nil if no run is currently active.
    def current_holder
      return nil unless File.exist?(@path)

      probe = File.open(@path, File::RDWR)
      begin
        if probe.flock(File::LOCK_EX | File::LOCK_NB)
          probe.flock(File::LOCK_UN)
          nil
        else
          content = probe.read
          content.nil? || content.strip.empty? ? {} : JSON.parse(content)
        end
      ensure
        probe.close
      end
    rescue Errno::ENOENT
      nil
    end

    private

    def write_metadata(metadata)
      @file.truncate(0)
      @file.rewind
      @file.write(JSON.generate(metadata))
      @file.flush
    end
  end
end
