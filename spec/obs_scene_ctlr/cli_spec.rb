require "spec_helper"
require "yaml"

RSpec.describe ObsSceneCtlr::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @config_path = File.join(@dir, "config.yml")
      File.write(@config_path, YAML.dump(
        "obs" => { "host" => "localhost", "port" => 4455, "password" => nil },
        "main_scene" => "MAIN CAMERA",
        "max_commercial_duration" => 30,
        "playlists" => { "main" => %w[A B C] }
      ))
      example.run
    end
  end

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run_cli(*args)
    original_default_path = ObsSceneCtlr::Config::DEFAULT_PATH
    original_default_root = ObsSceneCtlr::Config::DEFAULT_ROOT_DIR
    stub_const("ObsSceneCtlr::Config::DEFAULT_PATH", @config_path)
    stub_const("ObsSceneCtlr::Config::DEFAULT_ROOT_DIR", @dir)
    described_class.new(args, out: out, err: err).run
  ensure
    stub_const("ObsSceneCtlr::Config::DEFAULT_PATH", original_default_path)
    stub_const("ObsSceneCtlr::Config::DEFAULT_ROOT_DIR", original_default_root)
  end

  it "prints usage and exits non-zero with no command" do
    expect(run_cli).to eq(1)
    expect(err.string).to include("Usage:")
  end

  it "rejects an unknown playlist" do
    expect(run_cli("status", "halftime")).to eq(1)
    expect(err.string).to include("Unknown playlist")
  end

  it "reports IDLE and per-playlist next-up when nothing is running" do
    expect(run_cli("status")).to eq(0)
    expect(out.string).to include("IDLE")
    expect(out.string).to include("[main] last_played=none next_up=A")
  end

  it "reports no run in progress for stop when idle" do
    expect(run_cli("stop")).to eq(0)
    expect(out.string).to include("No run in progress.")
  end

  it "resets a playlist's rotation" do
    state = ObsSceneCtlr::StateStore.new("main", state_dir: File.join(@dir, "state"))
    state.record_play!(1, "B")

    expect(run_cli("reset")).to eq(0)
    expect(out.string).to include("reset")

    reloaded = ObsSceneCtlr::StateStore.new("main", state_dir: File.join(@dir, "state"))
    expect(reloaded.last_played_index).to eq(-1)
  end

  it "refuses to reset while a run is active" do
    run_lock = ObsSceneCtlr::RunLock.new(run_dir: File.join(@dir, "run"))
    run_lock.try_acquire("pid" => 1, "mode" => "loop", "playlist" => "main")

    expect(run_cli("reset")).to eq(1)
    expect(err.string).to include("Cannot reset while a run is active")
  end

  it "aborts via dry-run OBS client and reports success" do
    original_dry_run = ENV["OBS_DRY_RUN"]
    ENV["OBS_DRY_RUN"] = "1"

    expect(run_cli("abort")).to eq(0)
    expect(out.string).to include("Aborted")
  ensure
    ENV["OBS_DRY_RUN"] = original_dry_run
  end

  describe "populate" do
    around do |example|
      original_dry_run = ENV["OBS_DRY_RUN"]
      ENV["OBS_DRY_RUN"] = "1"
      example.run
    ensure
      ENV["OBS_DRY_RUN"] = original_dry_run
    end

    it "writes main_scene and the playlist fetched from OBS into config.yml" do
      expect(run_cli("populate", "main")).to eq(0)
      expect(out.string).to include("Populated playlist 'main'")

      raw = YAML.safe_load(File.read(@config_path))
      expect(raw["main_scene"]).to eq("Camera Scene")
      expect(raw["playlists"]["main"]).to eq(["COMM - 01 - Sponsor A", "COMM - 02 - Sponsor B", "COMM - 03 - Sponsor C"])
      expect(raw["playlists"]["main"]).not_to include("Camera Scene")
    end

    it "can create a brand-new playlist that did not previously exist in config.yml" do
      expect(run_cli("populate", "pregame")).to eq(0)

      raw = YAML.safe_load(File.read(@config_path))
      expect(raw["playlists"]).to have_key("pregame")
      expect(raw["playlists"]).to have_key("main")
    end

    it "refuses to populate while a run is active" do
      run_lock = ObsSceneCtlr::RunLock.new(run_dir: File.join(@dir, "run"))
      run_lock.try_acquire("pid" => 1, "mode" => "loop", "playlist" => "main")

      expect(run_cli("populate", "main")).to eq(1)
      expect(err.string).to include("Cannot populate while a run is active")
    end
  end
end
