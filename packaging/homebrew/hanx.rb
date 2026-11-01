class Hanx < Formula
  desc "Local office document CLI, desktop setup, and MCP tools"
  homepage "https://studentsview.github.io/HanX/"
  version "2.9.0"
  license "MIT"

  on_macos do
    url "https://github.com/StudentsView/HanX/releases/download/v2.9.0/HanX-CLI-2.9.0-macOS.zip"
    sha256 "279d26cd4110020a52f26953707b8bd9e08df5941a27d9834626a8cf81dd6294"
    depends_on :macos => :ventura
  end
  on_linux do
    on_intel do
      url "https://github.com/StudentsView/HanX/releases/download/v2.9.0/HanX-CLI-2.9.0-linux-x64.tar.gz"
      sha256 "7f13d8abb3e0114f53311502a59c96ec37adb54be835e68d844ee222b1547694"
    end
  end
  depends_on "node"

  resource "setup" do
    url "https://github.com/StudentsView/HanX/releases/download/v2.9.0/HanX-Setup-2.9.0.tar.gz"
    sha256 "4d4b96f967ef7be0faa63e9ec77abaec4c450d0ea9049099f0351663e742d8cd"
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
