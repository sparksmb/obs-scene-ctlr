require "spec_helper"
require "yaml"

RSpec.describe ObsSceneCtlr::Config do
  let(:valid_data) do
    {
      "obs" => { "host" => "localhost", "port" => 4455, "password" => "secret" },
      "main_scene" => "MAIN CAMERA",
      "max_commercial_duration" => 30,
      "playlists" => { "main" => %w[A B C] }
    }
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write_config(data)
    path = File.join(@dir, "config.yml")
    File.write(path, YAML.dump(data))
    path
  end

  it "loads a valid config" do
    path = write_config(valid_data)
    config = described_class.load(path, root_dir: @dir)

    expect(config.obs_host).to eq("localhost")
    expect(config.obs_port).to eq(4455)
    expect(config.obs_password).to eq("secret")
    expect(config.main_scene).to eq("MAIN CAMERA")
    expect(config.max_commercial_duration).to eq(30)
    expect(config.scenes_for("main")).to eq(%w[A B C])
    expect(config.playlist?("main")).to be true
    expect(config.playlist?("pregame")).to be false
  end

  it "raises when the config file is missing" do
    expect do
      described_class.load(File.join(@dir, "missing.yml"), root_dir: @dir)
    end.to raise_error(ObsSceneCtlr::ConfigError, /not found/)
  end

  it "raises when playlists is missing" do
    data = valid_data.reject { |k, _| k == "playlists" }
    path = write_config(data)

    expect do
      described_class.load(path, root_dir: @dir)
    end.to raise_error(ObsSceneCtlr::ConfigError, /playlists/)
  end

  it "raises when a playlist is empty" do
    data = valid_data.merge("playlists" => { "main" => [] })
    path = write_config(data)

    expect do
      described_class.load(path, root_dir: @dir)
    end.to raise_error(ObsSceneCtlr::ConfigError, /non-empty/)
  end

  it "raises for scenes_for on an unknown playlist" do
    path = write_config(valid_data)
    config = described_class.load(path, root_dir: @dir)

    expect { config.scenes_for("halftime") }.to raise_error(ObsSceneCtlr::ConfigError, /Unknown playlist/)
  end

  it "exposes state_dir and run_dir under root_dir" do
    path = write_config(valid_data)
    config = described_class.load(path, root_dir: @dir)

    expect(config.state_dir).to eq(File.join(@dir, "state"))
    expect(config.run_dir).to eq(File.join(@dir, "run"))
  end

  it "exposes the source_path it was loaded from" do
    path = write_config(valid_data)
    config = described_class.load(path, root_dir: @dir)

    expect(config.source_path).to eq(path)
  end

  it "defaults media_sources to empty and media_source_override to nil when not configured" do
    path = write_config(valid_data)
    config = described_class.load(path, root_dir: @dir)

    expect(config.media_sources).to eq({})
    expect(config.media_source_override("A")).to be_nil
  end

  it "exposes a configured media_sources override" do
    data = valid_data.merge("media_sources" => { "A" => "a_audio.mp3" })
    path = write_config(data)
    config = described_class.load(path, root_dir: @dir)

    expect(config.media_source_override("A")).to eq("a_audio.mp3")
    expect(config.media_source_override("B")).to be_nil
  end

  it "raises when media_sources is not a mapping" do
    data = valid_data.merge("media_sources" => ["not", "a", "hash"])
    path = write_config(data)

    expect do
      described_class.load(path, root_dir: @dir)
    end.to raise_error(ObsSceneCtlr::ConfigError, /media_sources must be a mapping/)
  end

  it "raises when a media_sources value is empty" do
    data = valid_data.merge("media_sources" => { "A" => "" })
    path = write_config(data)

    expect do
      described_class.load(path, root_dir: @dir)
    end.to raise_error(ObsSceneCtlr::ConfigError, /media_sources\['A'\]/)
  end
end
