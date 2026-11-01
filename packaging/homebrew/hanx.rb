class Hanx < Formula
  desc "Local office document CLI, desktop setup, and MCP tools"
  homepage "https://studentsview.github.io/HanX/"
  version "2.9.1"
  license "MIT"

  on_macos do
    url "https://github.com/StudentsView/HanX/releases/download/v2.9.1/HanX-CLI-2.9.1-macOS.zip"
    sha256 "4d932b65a5d7e64c9d881a8ad1265d4ab76d7bb239cbfb0ae2a9ad49d01cfb79"
    depends_on :macos => :ventura
  end
  on_linux do
    on_intel do
      url "https://github.com/StudentsView/HanX/releases/download/v2.9.1/HanX-CLI-2.9.1-linux-x64.tar.gz"
      sha256 "55cade490dade194df50e23aeb5219f6d752a93922fc37817afcca8012b09396"
    end
  end
  depends_on "node"

  resource "setup" do
    url "https://github.com/StudentsView/HanX/releases/download/v2.9.1/HanX-Setup-2.9.1.tar.gz"
    sha256 "5989fe2b87a63d74f902bc9c66f8bbd80f643ade4175b126b16862fa17b9386a"
  end

  def install
    platform = OS.mac? ? "darwin" : "linux"
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    native = libexec/"native/#{platform}-#{arch}"
    native.install Dir["*"]
    resource("setup").stage { libexec.install "bin", "lib", "package.json" }
    (bin/"hanx").write <<~SH
      #!/bin/sh
      exec "#{Formula["node"].opt_bin}/node" "#{libexec}/bin/hanx.js" "$@"
    SH
    bin.install_symlink "hanx" => "hanx-cli"
    pkgshare.install native/"LICENSE", native/"NOTICE"
  end

  def caveats
    <<~EOS
      CLI is ready. Run `hanx setup` to choose CLI only, GUI only, or both.
      Homebrew lifecycle installation never blocks on a prompt and never downloads a GUI.
      GUI-only keeps the small setup launcher and disables terminal document commands.
      The desktop app retains an internal engine. Linux GUI installation is per-user.
      PDF export may require a compatible local renderer; none is installed automatically.
    EOS
  end

  test do
    require "json"
    assert_equal version.to_s, JSON.parse(shell_output("#{bin}/hanx --version"))["data"]["version"]
    (testpath/"spec.json").write(JSON.generate({kind: "spreadsheet", sheets: [{name: "Data", rows: [[2], [4]], cells: {"B1" => "=SUM(A1:A2)"}}]}))
    system bin/"hanx", "create", "--spec", testpath/"spec.json", "--output", testpath/"test.xlsx"
    data = JSON.parse(shell_output("#{bin}/hanx spreadsheet read #{testpath}/test.xlsx --sheet Data --range B1"))
    assert_equal 6, data["data"]["cells"][0]["value"]
  end
end
