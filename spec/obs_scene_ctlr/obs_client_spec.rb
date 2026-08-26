require "spec_helper"

RSpec.describe ObsSceneCtlr::ObsClient do
  subject(:client) { described_class.new(host: "localhost", port: 4455, password: nil, dry_run: true) }

  it "is in dry-run mode when constructed with dry_run: true" do
    expect(client.dry_run?).to be true
  end

  it "does not raise and returns true for switch_scene in dry-run mode" do
    expect(client.switch_scene("MAIN CAMERA")).to be true
  end

  it "returns a sample scene list including 'Camera Scene' in dry-run mode" do
    scenes = client.list_scene_names

    expect(scenes).to include("Camera Scene")
    expect(scenes.length).to be > 1
  end

  it "assumes a scene's media input shares its name in dry-run mode" do
    expect(client.scene_media_input("COMM - 01 - Sponsor A")).to eq("COMM - 01 - Sponsor A")
  end

  it "simulates 'still playing' then 'ended' for media_ended? in dry-run mode" do
    expect(client.media_ended?("COMM - 01 - Sponsor A")).to be false
    expect(client.media_ended?("COMM - 01 - Sponsor A")).to be true
  end

  it "does not raise and returns true for restart_media_input in dry-run mode" do
    expect(client.restart_media_input("COMM - 01 - Sponsor A")).to be true
  end

  it "resets the simulated media_ended? cycle for an input after restarting it" do
    expect(client.media_ended?("COMM - 01 - Sponsor A")).to be false
    expect(client.media_ended?("COMM - 01 - Sponsor A")).to be true

    client.restart_media_input("COMM - 01 - Sponsor A")

    expect(client.media_ended?("COMM - 01 - Sponsor A")).to be false
  end

  it "tracks media_ended? polls independently per input name" do
    expect(client.media_ended?("Sponsor A")).to be false
    expect(client.media_ended?("Sponsor B")).to be false
    expect(client.media_ended?("Sponsor A")).to be true
  end

  it "defaults dry_run based on the OBS_DRY_RUN environment variable" do
    original = ENV["OBS_DRY_RUN"]
    ENV["OBS_DRY_RUN"] = "1"

    expect(described_class.new(host: "localhost", port: 4455, password: nil).dry_run?).to be true
  ensure
    ENV["OBS_DRY_RUN"] = original
  end
end
