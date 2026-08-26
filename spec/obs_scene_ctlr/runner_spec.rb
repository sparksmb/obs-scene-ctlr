require "spec_helper"

# All fakes below report no media source by default (scene_media_input
# returns nil), so Runner falls back to a fixed poll_timeout wait capped at
# max_commercial_duration. Tests use max_commercial_duration: 0 so that
# fallback is instantaneous and specs stay fast.
module NoMediaDetected
  def scene_media_input(_scene_name)
    nil
  end
end

class FakeObsClient
  include NoMediaDetected

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
  include NoMediaDetected

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
  include NoMediaDetected

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
  include NoMediaDetected

  def switch_scene(_name)
    raise ObsSceneCtlr::ObsConnectionError, "boom"
  end
end

# Simulates a scene with a detectable media source. media_ended? returns
# false for the first (ends_after - 1) polls, then true, per input name.
class MediaAwareObsClient
  attr_reader :switches, :media_poll_counts, :restart_calls

  def initialize(ends_after: Hash.new(1))
    @switches = []
    @ends_after = ends_after
    @media_poll_counts = Hash.new(0)
    @restart_calls = []
  end

  def switch_scene(name)
    @switches << name
    true
  end

  def scene_media_input(scene_name)
    scene_name
  end

  def restart_media_input(input_name)
    @restart_calls << input_name
    @media_poll_counts[input_name] = 0
    true
  end

  def media_ended?(input_name)
    @media_poll_counts[input_name] += 1
    @media_poll_counts[input_name] >= @ends_after[input_name]
  end
end

# Always reports the media as still playing; used to exercise the
# safety-net max_commercial_duration timeout.
class NeverEndingObsClient
  attr_reader :switches

  def initialize
    @switches = []
  end

  def switch_scene(name)
    @switches << name
    true
  end

  def scene_media_input(scene_name)
    scene_name
  end

  def restart_media_input(_input_name)
    true
  end

  def media_ended?(_input_name)
    false
  end
end

# Used to prove that a config.yml media_sources override bypasses
# auto-detection entirely: scene_media_input raises if ever called.
class OverrideProbeObsClient
  attr_reader :switches, :restart_calls, :media_poll_counts

  def initialize
    @switches = []
    @restart_calls = []
    @media_poll_counts = Hash.new(0)
  end

  def switch_scene(name)
    @switches << name
    true
  end

  def scene_media_input(_scene_name)
    raise "scene_media_input should not be called when a media_sources override is configured"
  end

  def restart_media_input(input_name)
    @restart_calls << input_name
    true
  end

  def media_ended?(input_name)
    @media_poll_counts[input_name] += 1
    true
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
        "max_commercial_duration" => 0, # keep specs fast; poll_timeout returns immediately
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

  describe "media-ended detection" do
    let(:config) do
      ObsSceneCtlr::Config.new(
        {
          "obs" => { "host" => "localhost", "port" => 4455, "password" => nil },
          "main_scene" => "MAIN CAMERA",
          "max_commercial_duration" => 5,
          "playlists" => { "main" => scenes }
        },
        root_dir: @root_dir
      )
    end

    before do
      # Avoid real wall-clock delays from the poll loop's Kernel#sleep.
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    it "waits for the detected media source to report ended before advancing, " \
       "even for the last commercial in a bounded run (regression: previously skipped)" do
      obs_client = MediaAwareObsClient.new(ends_after: Hash.new(3))

      expect(build_runner(obs_client, count: 1).call).to be true

      expect(obs_client.media_poll_counts["Sponsor A"]).to eq(3)
      expect(obs_client.switches).to eq(["Sponsor A", "MAIN CAMERA"])
    end

    it "advances once media_ended? reports true for each commercial in a loop" do
      obs_client = MediaAwareObsClient.new(ends_after: Hash.new(2))

      expect(build_runner(obs_client, count: 2).call).to be true

      expect(obs_client.media_poll_counts).to eq("Sponsor A" => 2, "Sponsor B" => 2)
      expect(obs_client.switches).to eq(["Sponsor A", "Sponsor B", "MAIN CAMERA"])
    end

    it "gives up waiting via the safety-net max_commercial_duration if media never ends" do
      obs_client = NeverEndingObsClient.new

      expect(build_runner(obs_client, count: 1).call).to be true

      expect(obs_client.switches).to eq(["Sponsor A", "MAIN CAMERA"])
      expect(out.string).to include("did not report ended within 5s")
    end

    it "does NOT cut the current commercial short when stop is requested mid-wait; " \
       "lets it finish naturally, then returns to the main scene" do
      obs_client = MediaAwareObsClient.new(ends_after: Hash.new(3))
      allow(obs_client).to receive(:media_ended?).and_wrap_original do |method, input_name|
        control_flag.request_stop! if obs_client.media_poll_counts[input_name] == 1
        method.call(input_name)
      end

      expect(build_runner(obs_client, count: nil).call).to be true

      # All 3 polls happened (the commercial ran to its natural end, it
      # wasn't interrupted after the first poll where stop was requested),
      # and no second commercial started.
      expect(obs_client.media_poll_counts["Sponsor A"]).to eq(3)
      expect(obs_client.switches).to eq(["Sponsor A", "MAIN CAMERA"])
    end

    it "honors abort requested while waiting for media to end" do
      obs_client = MediaAwareObsClient.new(ends_after: Hash.new(100))
      allow(obs_client).to receive(:media_ended?).and_wrap_original do |method, input_name|
        control_flag.request_abort! if obs_client.media_poll_counts[input_name] == 1
        method.call(input_name)
      end

      expect(build_runner(obs_client, count: nil).call).to be true

      expect(obs_client.switches).to eq(["Sponsor A"])
    end

    it "restarts each commercial's media input before waiting for it to end" do
      obs_client = MediaAwareObsClient.new(ends_after: Hash.new(2))

      expect(build_runner(obs_client, count: 2).call).to be true

      expect(obs_client.restart_calls).to eq(["Sponsor A", "Sponsor B"])
    end

    it "uses a config.yml media_sources override instead of auto-detecting the scene's source" do
      overriding_config = ObsSceneCtlr::Config.new(
        {
          "obs" => { "host" => "localhost", "port" => 4455, "password" => nil },
          "main_scene" => "MAIN CAMERA",
          "max_commercial_duration" => 5,
          "playlists" => { "main" => scenes },
          "media_sources" => { "Sponsor A" => "custom_audio.mp3" }
        },
        root_dir: @root_dir
      )
      obs_client = OverrideProbeObsClient.new
      runner = described_class.new(
        config: overriding_config,
        obs_client: obs_client,
        run_lock: ObsSceneCtlr::RunLock.new(run_dir: overriding_config.run_dir),
        control_flag: ObsSceneCtlr::ControlFlag.new(run_dir: overriding_config.run_dir),
        playlist_name: "main",
        count: 1,
        out: out
      )

      expect(runner.call).to be true

      expect(obs_client.restart_calls).to eq(["custom_audio.mp3"])
      expect(obs_client.media_poll_counts).to eq("custom_audio.mp3" => 1)
    end
  end
end
