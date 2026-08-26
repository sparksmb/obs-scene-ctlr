require "spec_helper"

RSpec.describe ObsSceneCtlr::RunLock do
  around do |example|
    Dir.mktmpdir do |dir|
      @run_dir = dir
      example.run
    end
  end

  it "reports no holder when nothing has acquired the lock" do
    lock = described_class.new(run_dir: @run_dir)

    expect(lock.current_holder).to be_nil
  end

  it "acquires the lock when free" do
    lock = described_class.new(run_dir: @run_dir)

    expect(lock.try_acquire("pid" => 123, "mode" => "loop", "playlist" => "main")).to be true
  end

  it "prevents a second acquire while held, exposing holder metadata" do
    holder_lock = described_class.new(run_dir: @run_dir)
    holder_lock.try_acquire("pid" => 111, "mode" => "loop", "playlist" => "main")

    challenger_lock = described_class.new(run_dir: @run_dir)
    expect(challenger_lock.try_acquire("pid" => 222, "mode" => "count", "playlist" => "main")).to be false

    holder = challenger_lock.current_holder
    expect(holder["pid"]).to eq(111)
    expect(holder["mode"]).to eq("loop")
  end

  it "allows acquisition again after release" do
    holder_lock = described_class.new(run_dir: @run_dir)
    holder_lock.try_acquire("pid" => 111, "mode" => "loop", "playlist" => "main")
    holder_lock.release!

    expect(described_class.new(run_dir: @run_dir).current_holder).to be_nil

    next_lock = described_class.new(run_dir: @run_dir)
    expect(next_lock.try_acquire("pid" => 222, "mode" => "count", "playlist" => "main")).to be true
  end
end
