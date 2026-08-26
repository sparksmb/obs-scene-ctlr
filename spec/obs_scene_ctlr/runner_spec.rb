require "spec_helper"

class FakeObsClient
  attr_reader :switches

  def initialize
    @switches = []
  end

  def switch_scene(name)
    @switches << name
    true
  end
end

class StoppingObsClient
  attr_reader :switches

  def initialize(control_flag, stop_after:)
    @control_flag = control_flag
    @stop_after = stop_after
    @switches = []
  end

  def switch_scene(name)
    @switches << name
    @control_flag.request_stop! if @switches.size == @stop_after
    true
  end
end

class AbortingObsClient
  attr_reader :switches

  def initialize(control_flag, abort_after:)
    @control_flag = control_flag
    @abort_after = abort_after
    @switches = []
  end

  def switch_scene(name)
    @switches << name
    @control_flag.request_abort! if @switches.size == @abort_after
    true
  end
end

class FailingObsClient
  def switch_scene(_name)
    raise ObsSceneCtlr::ObsConnectionError, "boom"
  end
end

RSpec.describe ObsSceneCtlr::Runner do
  let(:scenes) { ["Sponsor A", "Sponsor B", "Sponsor C"] }

  around do |example|
    Dir.mktmpdir do |dir|
      @root_dir = dir
      example.run
    end
  end

  let(:config) do
    ObsSceneCtlr::Config.new(
      {
        "obs" => { "host" => "localhost", "port" => 4455, "password" => nil },
        "main_scene" => "MAIN CAMERA",
        "commercial_duration" => 0, # keep specs fast; poll_wait returns immediately
        "playlists" => { "main" => scenes }
      },
      root_dir: @root_dir
    )
  end

  let(:control_flag) { ObsSceneCtlr::ControlFlag.new(run_dir: config.run_dir) }
  let(:out) { StringIO.new }

  def build_runner(obs_client, count:, run_lock: ObsSceneCtlr::RunLock.new(run_dir: config.run_dir))
    described_class.new(
      config: config,
      obs_client: obs_client,
      run_lock: run_lock,
      control_flag: control_flag,
      playlist_name: "main",
      count: count,
      out: out
    )
  end

  it "plays exactly N commercials in rotation order, then returns to the main scene" do
    obs_client = FakeObsClient.new

    expect(build_runner(obs_client, count: 2).call).to be true

    expect(obs_client.switches).to eq(["Sponsor A", "Sponsor B", "MAIN CAMERA"])
  end

  it "releases the lock after finishing so a subsequent run can continue the rotation" do
    obs_client = FakeObsClient.new

    build_runner(obs_client, count: 2).call
    build_runner(obs_client, count: 1).call

    expect(obs_client.switches).to eq(
      ["Sponsor A", "Sponsor B", "MAIN CAMERA", "Sponsor C", "MAIN CAMERA"]
    )
  end

  it "refuses to start when the global lock is already held" do
    busy_lock = ObsSceneCtlr::RunLock.new(run_dir: config.run_dir)
    busy_lock.try_acquire("pid" => 999, "mode" => "loop", "playlist" => "main")

    obs_client = FakeObsClient.new
    result = build_runner(obs_client, count: 1, run_lock: ObsSceneCtlr::RunLock.new(run_dir: config.run_dir)).call

    expect(result).to be false
    expect(obs_client.switches).to be_empty
  end

  it "stops gracefully after the current commercial and returns to the main scene" do
    obs_client = StoppingObsClient.new(control_flag, stop_after: 2)

    expect(build_runner(obs_client, count: nil).call).to be true

    expect(obs_client.switches).to eq(["Sponsor A", "Sponsor B", "MAIN CAMERA"])
  end

  it "aborts immediately without the runner issuing its own extra main-scene switch" do
    obs_client = AbortingObsClient.new(control_flag, abort_after: 1)

    expect(build_runner(obs_client, count: nil).call).to be true

    expect(obs_client.switches).to eq(["Sponsor A"])
  end

  it "does not persist rotation state and releases the lock when OBS fails" do
    obs_client = FailingObsClient.new
    run_lock = ObsSceneCtlr::RunLock.new(run_dir: config.run_dir)

    expect(build_runner(obs_client, count: 1, run_lock: run_lock).call).to be false

    expect(run_lock.current_holder).to be_nil
    state = ObsSceneCtlr::StateStore.new("main", state_dir: config.state_dir)
    expect(state.last_played_index).to eq(-1)
  end
end
