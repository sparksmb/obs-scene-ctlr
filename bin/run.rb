#!/usr/bin/env ruby

require_relative "../lib/obs_scene_ctlr/cli"
require_relative "../lib/obs_scene_ctlr/tee_logger"

# Mirror all output to a shared log file so invocations triggered from
# somewhere with no visible terminal (e.g. a Stream Deck button) still
# leave a record. Tail it with:
#   tail -f logs/controller.log
LOG_PATH = File.expand_path("../logs/controller.log", __dir__)
$stdout = ObsSceneCtlr::TeeLogger.new($stdout, log_path: LOG_PATH)
$stderr = ObsSceneCtlr::TeeLogger.new($stderr, log_path: LOG_PATH)

$stdout.puts "== run.rb #{ARGV.join(' ')} (pid #{Process.pid}) =="

exit(ObsSceneCtlr::CLI.new(ARGV).run)
