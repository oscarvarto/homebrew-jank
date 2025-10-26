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
  depends_on "llvm@21"
  depends_on "openssl"

  skip_clean "bin/jank"

  def install
    ENV.prepend_path "PATH", Formula["llvm@21"].opt_bin

    # Critical: Ensure libc++ headers come BEFORE SDK headers
    # This fixes the macOS 26 header ordering issue (jank-lang/jank#560)
    llvm_include = Formula["llvm@21"].opt_include
    ENV.prepend "CPPFLAGS", "-isystem #{llvm_include}/c++/v1"
    ENV.prepend "CXXFLAGS", "-isystem #{llvm_include}/c++/v1"

    # Use LLVM's clang explicitly on macOS to avoid Homebrew clang issues
    if OS.mac?
      ENV["CC"] = Formula["llvm@21"].opt_bin/"clang"
      ENV["CXX"] = Formula["llvm@21"].opt_bin/"clang++"
      ENV["SDKROOT"] = MacOS.sdk_path
    else
      ENV["CC"] = Formula["llvm@21"].opt_bin/"clang"
      ENV["CXX"] = Formula["llvm@21"].opt_bin/"clang++"
    end

    ENV.append "LDFLAGS", "-Wl,-rpath,#{Formula["llvm@21"].opt_lib}"
    ENV.append "LDFLAGS", "-L#{Formula["llvm@21"].opt_lib}"

    ENV.append "CPPFLAGS", "-I#{llvm_include}"
    ENV.append "CPPFLAGS", "-fno-sized-deallocation"

    cd "compiler+runtime"

    system "./bin/configure",
           "-GNinja",
           *std_cmake_args,
           "-DHOMEBREW_ALLOW_FETCHCONTENT=ON",
           "-DCMAKE_CXX_COMPILER=#{Formula["llvm@21"].opt_bin}/clang++",
           "-DCMAKE_C_COMPILER=#{Formula["llvm@21"].opt_bin}/clang"
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
