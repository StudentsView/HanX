class Hanword < Formula
  desc "Local macOS office CLI and MCP tools for spreadsheet formulas and documents"
  homepage "https://studentsview.github.io/HanWord/"
  url "https://github.com/StudentsView/HanWord/releases/download/v2.6.0/HanWord-CLI-2.6.0-macOS.zip"
  version "2.6.0"
  sha256 "525043a245843e4ec5265bf6562d841ce9c94407320679bdcec288e03a132cd1"
  license "MIT"
  depends_on :macos => :ventura

  def install
    bin.install "hanword"
    bin.install_symlink "hanword" => "hanword-cli"
    (prefix/"docs/cli").install "README.md", "examples"
    pkgshare.install "LICENSE", "NOTICE"
  end

  test do
    require "json"
    assert_equal version.to_s, JSON.parse(shell_output("#{bin}/hanword --version"))["data"]["version"]
    (testpath/"spec.json").write(JSON.generate({kind: "spreadsheet", sheets: [{name: "Data", rows: [[2], [4]], cells: {"B1" => "=SUM(A1:A2)"}}]}))
    system bin/"hanword", "create", "--spec", testpath/"spec.json", "--output", testpath/"test.xlsx"
    data = JSON.parse(shell_output("#{bin}/hanword spreadsheet read #{testpath}/test.xlsx --sheet Data --range B1"))
    assert_equal 6, data["data"]["cells"][0]["value"]
  end
end
