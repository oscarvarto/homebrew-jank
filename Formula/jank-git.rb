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
  depends_on "llvm"
  depends_on "openssl"

  skip_clean "bin/jank"

  def install
    # Clear Nix-provided compiler flags that point to old SDK (11.3)
    # This is critical when building on systems with Nix installed
    # These variables interfere with proper SDK and libc++ header resolution
    ENV.delete("NIX_CFLAGS_COMPILE")
    ENV.delete("NIX_LDFLAGS")
    ENV.delete("NIX_APPLE_SDK_VERSION")
    ENV.delete("SDKROOT") # Clear Nix's SDKROOT pointing to old SDK

    # Use Homebrew's LLVM (not system clang, not Nix clang)
    llvm = Formula["llvm"]
    ENV.prepend_path "PATH", llvm.opt_bin
    ENV["CC"] = llvm.opt_bin/"clang"
    ENV["CXX"] = llvm.opt_bin/"clang++"

    # Use system Xcode SDK for macOS headers/frameworks (not Nix SDK)
    # This fixes the macOS 26 header ordering issue (jank-lang/jank#560)
    if OS.mac?
      ENV["SDKROOT"] = MacOS.sdk_path
      ENV["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    end

    # Critical: Ensure Homebrew LLVM's libc++ headers come BEFORE SDK C headers
    # Use -isystem for libc++ to prioritize it, -I for other LLVM includes
    llvm_include = llvm.opt_include
    llvm_lib = llvm.opt_lib

    # Build flags with proper header search order
    ENV["CPPFLAGS"] = "-isystem #{llvm_include}/c++/v1 -I#{llvm_include} -fno-sized-deallocation"
    ENV["CXXFLAGS"] = "-isystem #{llvm_include}/c++/v1"
    ENV["LDFLAGS"] = "-L#{llvm_lib} -Wl,-rpath,#{llvm_lib}"

    cd "compiler+runtime"

    system "./bin/configure",
           "-GNinja",
           *std_cmake_args,
           "-DHOMEBREW_ALLOW_FETCHCONTENT=ON",
           "-DCMAKE_CXX_COMPILER=#{llvm.opt_bin}/clang++",
           "-DCMAKE_C_COMPILER=#{llvm.opt_bin}/clang"
    system "./bin/compile"
    system "./bin/install"
  end

  test do
    jank = bin/"jank"

    assert_predicate jank, :exist?, "jank must exist"
    assert_predicate jank, :executable?, "jank must be executable"

    health_check = pipe_output("#{jank} check-health")
    assert_match "jank can aot compile working binaries", health_check
  end
end
