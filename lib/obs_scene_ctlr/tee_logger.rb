require "fileutils"
require "time"

module ObsSceneCtlr
  # Wraps an IO (typically $stdout or $stderr) so every line written through
  # it is also appended, with a UTC timestamp, to a shared log file.
  #
  # This exists so invocations triggered from something like a Stream Deck
  # button (which has no visible terminal) still leave a record of what
  # happened. Everything else behaves like the wrapped IO: it's forwarded
  # via method_missing, so callers can keep using puts/print/warn as usual.
  class TeeLogger
    def initialize(io, log_path:)
      @io = io
      @log_path = log_path
      begin
        FileUtils.mkdir_p(File.dirname(@log_path))
      rescue StandardError
        nil
      end
    end

    def puts(*args)
      args = [nil] if args.empty?
      args.each do |arg|
        line = arg.to_s
        @io.puts(arg)
        append_to_log(line)
      end
    end

    def write(*args)
      args.each { |arg| append_to_log(arg.to_s) }
      @io.write(*args)
    end

    def method_missing(name, *args, &block)
      @io.send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      @io.respond_to?(name, include_private) || super
    end

    private

    def append_to_log(text)
      return if text.nil? || text.empty?

      File.open(@log_path, "a") do |f|
        text.each_line do |line|
          next if line.chomp.empty?

          f.puts("[#{Time.now.utc.iso8601}] #{line.chomp}")
        end
      end
    rescue StandardError
      # Never let logging failures break the actual command.
      nil
    end
  end
end
