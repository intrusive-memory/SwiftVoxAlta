# typed: false
# frozen_string_literal: true

# Homebrew formula for diga — AI voice designer for screenwriters.
# Pre-built binary distribution for Apple Silicon Macs.
class Diga < Formula
  desc "AI voice designer for screenwriters — design and clone character voices with Qwen3-TTS"
  homepage "https://github.com/intrusive-memory/SwiftVoxAlta"
  version "0.1.0"
  license "MIT"

  url "https://github.com/intrusive-memory/SwiftVoxAlta/releases/download/v#{version}/diga-#{version}-arm64-macos.tar.gz"
  sha256 "PLACEHOLDER_SHA256"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  def install
    libexec.install "diga"
    libexec.install "mlx-swift_Cmlx.bundle"

    # Wrapper script that sets bundle path for Metal shader discovery
    (bin/"diga").write <<~SH
      #!/bin/bash
      exec "#{libexec}/diga" "$@"
    SH
  end

  def caveats
    <<~EOS
      diga requires Apple Silicon (M1 or later) and macOS Tahoe (26.0+).

      On first run, diga will download the Qwen3-TTS model (~3.5 GB)
      from Hugging Face to ~/.cache/huggingface/hub/. This is a one-time
      download and requires an internet connection.

      For convenience, you may want to add an alias:
        alias say-design='diga voice-design'
        alias say-clone='diga voice-clone'
    EOS
  end

  test do
    assert_match "diga", shell_output("#{bin}/diga --version")
  end
end
