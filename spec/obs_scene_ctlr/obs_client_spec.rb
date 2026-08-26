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

  it "defaults dry_run based on the OBS_DRY_RUN environment variable" do
    original = ENV["OBS_DRY_RUN"]
    ENV["OBS_DRY_RUN"] = "1"

    expect(described_class.new(host: "localhost", port: 4455, password: nil).dry_run?).to be true
  ensure
    ENV["OBS_DRY_RUN"] = original
  end
end
