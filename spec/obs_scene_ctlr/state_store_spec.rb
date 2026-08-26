require "spec_helper"

RSpec.describe ObsSceneCtlr::StateStore do
  around do |example|
    Dir.mktmpdir do |dir|
      @state_dir = dir
      example.run
    end
  end

  it "creates a fresh state file with last_played_index -1 when missing" do
    store = described_class.new("main", state_dir: @state_dir)

    expect(store.last_played_index).to eq(-1)
    expect(store.last_played_scene).to be_nil
    expect(File.exist?(File.join(@state_dir, "main.json"))).to be true
  end

  it "computes next_index as 0 before anything has played" do
    store = described_class.new("main", state_dir: @state_dir)

    expect(store.next_index(6)).to eq(0)
  end

  it "wraps around to 0 after the last scene" do
    store = described_class.new("main", state_dir: @state_dir)
    store.record_play!(5, "Sponsor F")

    expect(store.next_index(6)).to eq(0)
  end

  it "persists last played scene/index across instances" do
    store = described_class.new("main", state_dir: @state_dir)
    store.record_play!(2, "Sponsor C")

    reloaded = described_class.new("main", state_dir: @state_dir)
    expect(reloaded.last_played_index).to eq(2)
    expect(reloaded.last_played_scene).to eq("Sponsor C")
    expect(reloaded.next_index(6)).to eq(3)
  end

  it "resets rotation back to -1" do
    store = described_class.new("main", state_dir: @state_dir)
    store.record_play!(3, "Sponsor D")

    store.reset!

    expect(store.last_played_index).to eq(-1)
    expect(store.next_index(6)).to eq(0)
  end

  it "keeps separate state per playlist" do
    main = described_class.new("main", state_dir: @state_dir)
    pregame = described_class.new("pregame", state_dir: @state_dir)

    main.record_play!(0, "Sponsor A")

    expect(main.last_played_index).to eq(0)
    expect(pregame.last_played_index).to eq(-1)
  end
end
