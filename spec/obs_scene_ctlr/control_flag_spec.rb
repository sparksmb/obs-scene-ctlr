require "spec_helper"

RSpec.describe ObsSceneCtlr::ControlFlag do
  around do |example|
    Dir.mktmpdir do |dir|
      @run_dir = dir
      example.run
    end
  end

  it "has no requested action initially" do
    flag = described_class.new(run_dir: @run_dir)

    expect(flag.requested).to be_nil
    expect(flag.any_requested?).to be false
  end

  it "records a stop request" do
    flag = described_class.new(run_dir: @run_dir)

    flag.request_stop!

    expect(flag.stop_requested?).to be true
    expect(flag.abort_requested?).to be false
  end

  it "records an abort request, overriding a prior stop" do
    flag = described_class.new(run_dir: @run_dir)

    flag.request_stop!
    flag.request_abort!

    expect(flag.abort_requested?).to be true
    expect(flag.stop_requested?).to be false
  end

  it "clears the flag" do
    flag = described_class.new(run_dir: @run_dir)
    flag.request_stop!

    flag.clear!

    expect(flag.requested).to be_nil
    expect(flag.any_requested?).to be false
  end

  it "is visible to a separate instance pointed at the same run_dir" do
    writer = described_class.new(run_dir: @run_dir)
    reader = described_class.new(run_dir: @run_dir)

    writer.request_stop!

    expect(reader.stop_requested?).to be true
  end
end
