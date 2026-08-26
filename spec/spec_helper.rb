require "tmpdir"
require "stringio"

require_relative "../lib/obs_scene_ctlr/config"
require_relative "../lib/obs_scene_ctlr/state_store"
require_relative "../lib/obs_scene_ctlr/run_lock"
require_relative "../lib/obs_scene_ctlr/control_flag"
require_relative "../lib/obs_scene_ctlr/obs_client"
require_relative "../lib/obs_scene_ctlr/runner"
require_relative "../lib/obs_scene_ctlr/cli"
require_relative "../lib/obs_scene_ctlr/tee_logger"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
  Kernel.srand config.seed
end
