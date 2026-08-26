#!/usr/bin/env ruby

require_relative "../lib/obs_scene_ctlr/cli"

exit(ObsSceneCtlr::CLI.new(ARGV).run)
