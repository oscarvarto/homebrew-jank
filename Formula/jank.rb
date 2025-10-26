class Jank < Formula
  desc "The native Clojure dialect hosted on LLVM with seamless C++ interop."
  homepage "https://jank-lang.org"
  url "https://cache.jank-lang.org/jank_0.1-1_aarch64.tar.gz"
  version "0.1"
  license "MPL-2.0"

  depends_on "boost"
  depends_on "libzip"
  depends_on "openssl"

  skip_clean "bin/jank"

  def install
    (buildpath/"usr/local").cd do
      cp_r Dir["*"], prefix
    end

    libexec_bin = libexec/"bin"
    libexec_bin.install bin/"jank"
    (bin/"jank").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      unset SDKROOT
      unset HOMEBREW_SDKROOT
      unset MACOSX_DEPLOYMENT_TARGET
      unset NIX_CFLAGS_COMPILE
      unset NIX_LDFLAGS
      unset NIX_APPLE_SDK_VERSION
      unset NIX_APPLE_SDK_ROOT
      exec "#{libexec_bin/"jank"}" "$@"
    SH
    (bin/"jank").chmod 0755
    ln_s lib, libexec/"lib", force: true
  end

  test do
    jank = bin/"jank"

    assert_predicate jank, :exist?, "jank must exist"
    assert_predicate jank, :executable?, "jank must be executable"

    health_check = pipe_output("#{jank} check-health")
    assert_match "jank can aot compile working binaries", health_check
  end
end
