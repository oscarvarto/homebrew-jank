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

    # Use the full Xcode SDK for macOS headers/frameworks (not CommandLineTools)
    # Homebrew's MacOS.sdk_path returns the CLT SDK, so query xcrun directly.
    if OS.mac?
      sdk = Utils.safe_popen_read("/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path").strip
      developer_dir = Utils.safe_popen_read("/usr/bin/xcode-select", "--print-path").strip

      ENV["SDKROOT"] = sdk
      ENV["HOMEBREW_SDKROOT"] = sdk
      ENV["DEVELOPER_DIR"] = developer_dir

      # Patch CMakeLists so the generated JIT flags don't bake CommandLineTools paths.
      inreplace "compiler+runtime/CMakeLists.txt" do |s|
        s.sub!(
          "separate_arguments(clang_system_include_dirs)\n\nset(clang_system_include_flags \"\")",
          <<~'CMAKE'.chomp
            separate_arguments(clang_system_include_dirs)

            if(APPLE)
              set(_adjusted_dirs "")
              foreach(dir ${clang_system_include_dirs})
                if(dir MATCHES "/SDKs/")
                  # Skip SDK include paths; clang will find them via -isysroot.
                else()
                  list(APPEND _adjusted_dirs "${dir}")
                endif()
              endforeach()
              set(clang_system_include_dirs "${_adjusted_dirs}")
            endif()

            set(clang_system_include_flags "")
          CMAKE
        )
      end
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

    cmake_args = std_cmake_args
    cmake_args = cmake_args.reject { |arg| arg.start_with?("-DCMAKE_OSX_SYSROOT=") } if OS.mac?

    configure_args = [
      "-GNinja",
      *cmake_args,
      "-DHOMEBREW_ALLOW_FETCHCONTENT=ON",
      "-DCMAKE_CXX_COMPILER=#{llvm.opt_bin}/clang++",
      "-DCMAKE_C_COMPILER=#{llvm.opt_bin}/clang"
    ]
    configure_args << "-DCMAKE_OSX_SYSROOT=#{ENV["SDKROOT"]}" if OS.mac?

    system "./bin/configure", *configure_args
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
