class JankGit < Formula
  desc "The native Clojure dialect hosted on LLVM with seamless C++ interop."
  homepage "https://jank-lang.org"
  url "https://github.com/jank-lang/jank.git", branch: "main"
  version "0.1"
  license "MPL-2.0"

  depends_on "cmake" => :build
  depends_on "git-lfs" => :build
  depends_on "ninja" => :build

  depends_on "boost"
  depends_on "libzip"
  depends_on "oscarvarto/jank/llvm-head" => :head
  depends_on "openssl"

  skip_clean "bin/jank"

  def install
    # Use our custom LLVM HEAD formula
    llvm = Formula["oscarvarto/jank/llvm-head"]
    ENV.prepend_path "PATH", llvm.opt_bin
    ENV["CC"] = llvm.opt_bin/"clang"
    ENV["CXX"] = llvm.opt_bin/"clang++"

    # Use the Xcode SDK
    if OS.mac?
      sdk = Utils.safe_popen_read("/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path").strip
      developer_dir = Utils.safe_popen_read("/usr/bin/xcode-select", "--print-path").strip

      ENV["SDKROOT"] = sdk
      ENV["HOMEBREW_SDKROOT"] = sdk
      ENV["DEVELOPER_DIR"] = developer_dir
    end

    # LLVM paths for header and library search
    llvm_prefix = llvm.opt_prefix
    llvm_include = llvm.opt_include
    llvm_lib = llvm.opt_lib

    # Build flags with proper header search order
    # libc++ headers must come BEFORE SDK C headers
    # Also include the unwind library path
    ENV["CPPFLAGS"] = "-isystem #{llvm_include}/c++/v1 -I#{llvm_include}"
    ENV["CXXFLAGS"] = "-isystem #{llvm_include}/c++/v1"
    ENV["LDFLAGS"] = "-L#{llvm_lib} -L#{llvm_lib}/c++ -L#{llvm_lib}/unwind -Wl,-rpath,#{llvm_lib} -Wl,-rpath,#{llvm_lib}/c++ -Wl,-rpath,#{llvm_lib}/unwind"

    cmake_args = std_cmake_args
    cmake_args = cmake_args.reject { |arg| arg.start_with?("-DCMAKE_OSX_SYSROOT=") } if OS.mac?

    configure_args = [
      "-GNinja",
      *cmake_args,
      "-DHOMEBREW_ALLOW_FETCHCONTENT=ON",
      "-DCMAKE_CXX_COMPILER=#{llvm.opt_bin}/clang++",
      "-DCMAKE_C_COMPILER=#{llvm.opt_bin}/clang",
      "-DLLVM_DIR=#{llvm_lib}/cmake/llvm",
      "-DClang_DIR=#{llvm_lib}/cmake/clang",
      "-DMLIR_DIR=#{llvm_lib}/cmake/mlir",
    ]
    configure_args << "-DCMAKE_OSX_SYSROOT=#{ENV["SDKROOT"]}" if OS.mac?

    # Use Dir.chdir block form to avoid Ruby warning about nested chdir
    Dir.chdir("compiler+runtime") do
      system "./bin/configure", *configure_args
      system "./bin/compile"
      system "./bin/install"
    end

    libexec_bin = libexec/"bin"
    libexec_bin.install bin/"jank"
    (bin/"jank").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
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
