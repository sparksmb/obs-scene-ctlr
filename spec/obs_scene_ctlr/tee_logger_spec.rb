require "spec_helper"

RSpec.describe ObsSceneCtlr::TeeLogger do
  around do |example|
    Dir.mktmpdir do |dir|
      @log_path = File.join(dir, "nested", "controller.log")
      example.run
    end
  end

  it "forwards puts to the wrapped IO" do
    underlying = StringIO.new
    logger = described_class.new(underlying, log_path: @log_path)

    logger.puts "hello"

    expect(underlying.string).to include("hello")
  end

  it "creates the log directory and appends a timestamped line to the log file" do
    underlying = StringIO.new
    logger = described_class.new(underlying, log_path: @log_path)

    logger.puts "hello world"

    expect(File.exist?(@log_path)).to be true
    contents = File.read(@log_path)
    expect(contents).to match(/\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\] hello world/)
  end

  it "appends across multiple puts calls rather than overwriting" do
    underlying = StringIO.new
    logger = described_class.new(underlying, log_path: @log_path)

    logger.puts "first"
    logger.puts "second"

    lines = File.readlines(@log_path)
    expect(lines.size).to eq(2)
    expect(lines[0]).to include("first")
    expect(lines[1]).to include("second")
  end

  it "forwards unknown methods (e.g. warn-style writes) to the wrapped IO" do
    underlying = StringIO.new
    logger = described_class.new(underlying, log_path: @log_path)

    logger.write("plain write\n")

    expect(underlying.string).to include("plain write")
    expect(File.read(@log_path)).to include("plain write")
  end

  it "does not raise if the log file cannot be written" do
    underlying = StringIO.new
    logger = described_class.new(underlying, log_path: "/nonexistent/really/not/writable/controller.log")

    expect { logger.puts "still works" }.not_to raise_error
    expect(underlying.string).to include("still works")
  end
end
