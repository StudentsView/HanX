class Hanx < Formula
  desc "Local macOS office CLI and MCP tools for spreadsheet formulas and documents"
  homepage "https://studentsview.github.io/HanX/"
  url "https://github.com/StudentsView/HanX/releases/download/v2.7.0/HanX-CLI-2.7.0-macOS.zip"
  version "2.7.0"
  sha256 "3d93611062f7d12c5d66e70ec119b62881bb44efca7401c08fc1a43e9da8d69b"
  license "MIT"
  depends_on :macos => :ventura

  def install
    bin.install "hanx"
    bin.install_symlink "hanx" => "hanx-cli"
    (prefix/"docs/cli").install "README.md", "examples"
    pkgshare.install "LICENSE", "NOTICE"
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
