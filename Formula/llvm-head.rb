class LlvmHead < Formula
  desc "Next-gen compiler infrastructure (HEAD build with single-arch runtimes)"
  homepage "https://llvm.org/"
  license "Apache-2.0" => { with: "LLVM-exception" }
  head "https://github.com/llvm/llvm-project.git", branch: "main"

  keg_only :provided_by_macos

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "swig" => :build
  depends_on "python@3.14"
  depends_on "xz"
  depends_on "z3"
  depends_on "zstd"

  uses_from_macos "libedit"
  uses_from_macos "libffi"
  uses_from_macos "ncurses"
  uses_from_macos "zlib"

  def python3
    "python3.14"
  end

  def clang_config_file_dir
    etc/"clang"
  end

  def install
    # The clang bindings need a little help finding our libclang.
    inreplace "clang/bindings/python/clang/cindex.py",
              /^(\s*library_path\s*=\s*)None$/,
              "\\1'#{lib}'"

    projects = %w[
      clang
      clang-tools-extra
      lld
      lldb
      mlir
      polly
    ]

    # CRITICAL: Only build libcxx, libcxxabi, libunwind
    # Do NOT include compiler-rt - it triggers multi-arch builds that cause
    # the dual sysroot bug on macOS betas (-isysroot specified twice)
    runtimes = %w[
      libcxx
      libcxxabi
      libunwind
    ]

    python_versions = Formula.names
                             .select { |name| name.start_with? "python@" }
                             .map { |py| py.delete_prefix("python@") }
    site_packages = Language::Python.site_packages(python3).delete_prefix("lib/")

    # Get the SDK path - use Xcode SDK
    macos_sdk = if OS.mac?
      Utils.safe_popen_read("/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path").strip
    end

    # CRITICAL: Override Homebrew's SDK detection to use Xcode SDK
    # This prevents the CLT SDK from being used
    if OS.mac?
      ENV["HOMEBREW_SDKROOT"] = macos_sdk
      ENV["SDKROOT"] = macos_sdk
    end

    args = %W[
      -DLLVM_ENABLE_PROJECTS=#{projects.join(";")}
      -DLLVM_ENABLE_RUNTIMES=#{runtimes.join(";")}
      -DLLVM_POLLY_LINK_INTO_TOOLS=ON
      -DLLVM_LINK_LLVM_DYLIB=ON
      -DLLVM_ENABLE_EH=OFF
      -DLLVM_ENABLE_FFI=ON
      -DLLVM_ENABLE_RTTI=ON
      -DLLVM_INCLUDE_DOCS=OFF
      -DLLVM_INCLUDE_TESTS=OFF
      -DLLVM_INSTALL_UTILS=ON
      -DLLVM_ENABLE_Z3_SOLVER=ON
      -DLLVM_OPTIMIZED_TABLEGEN=ON
      -DLLVM_TARGETS_TO_BUILD=all
      -DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON
      -DLLVM_SOURCE_PREFIX=.
      -DLLDB_USE_SYSTEM_DEBUGSERVER=ON
      -DLLDB_ENABLE_PYTHON=ON
      -DLLDB_ENABLE_LUA=OFF
      -DLLDB_ENABLE_LZMA=ON
      -DLLDB_PYTHON_RELATIVE_PATH=libexec/#{site_packages}
      -DLIBOMP_INSTALL_ALIASES=OFF
      -DLIBCXX_INSTALL_MODULES=ON
      -DCLANG_PYTHON_BINDINGS_VERSIONS=#{python_versions.join(";")}
      -DLLVM_CREATE_XCODE_TOOLCHAIN=OFF
      -DCLANG_FORCE_MATCHING_LIBCLANG_SOVERSION=OFF
      -DCLANG_CONFIG_FILE_SYSTEM_DIR=#{clang_config_file_dir.relative_path_from(bin)}
      -DCLANG_CONFIG_FILE_USER_DIR=~/.config/clang
    ]

    if tap.present?
      args += %W[
        -DPACKAGE_VENDOR=#{tap.user}
        -DBUG_REPORT_URL=#{tap.issues_url}
      ]
    end

    runtimes_cmake_args = []

    if OS.mac?
      ohai "Using SDK: #{macos_sdk}"

      args << "-DFFI_INCLUDE_DIR=#{macos_sdk}/usr/include/ffi"
      args << "-DFFI_LIBRARY_DIR=#{macos_sdk}/usr/lib"

      libcxx_install_libdir = lib/"c++"
      libunwind_install_libdir = lib/"unwind"
      libcxx_rpaths = [loader_path, rpath(source: libcxx_install_libdir, target: libunwind_install_libdir)]

      args << "-DLLVM_BUILD_LLVM_C_DYLIB=ON"
      args << "-DLLVM_ENABLE_LIBCXX=ON"
      args << "-DLIBCXX_PSTL_BACKEND=libdispatch"
      args << "-DLIBCXX_INSTALL_LIBRARY_DIR=#{libcxx_install_libdir}"
      args << "-DLIBUNWIND_INSTALL_LIBRARY_DIR=#{libunwind_install_libdir}"
      args << "-DLIBCXXABI_INSTALL_LIBRARY_DIR=#{libcxx_install_libdir}"

      # Set sysroot for main build - MUST use Xcode SDK consistently
      args << "-DCMAKE_OSX_SYSROOT=#{macos_sdk}"
      args << "-DDEFAULT_SYSROOT=#{macos_sdk}"

      # Runtimes configuration - single arch only
      runtimes_cmake_args << "-DCMAKE_INSTALL_RPATH=#{libcxx_rpaths.join("|")}"
      runtimes_cmake_args << "-DCMAKE_OSX_SYSROOT=#{macos_sdk}"
    end

    args << "-DRUNTIMES_CMAKE_ARGS=#{runtimes_cmake_args.join(";")}" if runtimes_cmake_args.present?

    llvmpath = buildpath/"llvm"

    mkdir llvmpath/"build" do
      system "cmake", "-G", "Ninja", "..", *(std_cmake_args + args)
      system "cmake", "--build", "."
      system "cmake", "--build", ".", "--target", "install"
    end

    if OS.mac?
      # Get the version from `llvm-config` to get the correct HEAD version
      llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
      soversion = Version.new(llvm_version).major.to_s
      soversion << "git" if llvm_version.end_with?("git")

      # Build compiler-rt separately to avoid dual sysroot bug
      # Key: Use standalone build with explicit single-arch targeting
      ohai "Building compiler-rt builtins separately..."

      host_arch = Hardware::CPU.arch.to_s
      host_arch = "arm64" if host_arch == "aarch64"
      target_triple = "#{host_arch}-apple-darwin#{OS.kernel_version.major}"

      # compiler-rt expects to install to lib/clang/<version>/lib/darwin/
      compiler_rt_install_prefix = lib/"clang"/soversion

      compiler_rt_args = %W[
        -DCOMPILER_RT_STANDALONE_BUILD=ON
        -DCOMPILER_RT_BUILD_BUILTINS=ON
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF
        -DCOMPILER_RT_BUILD_XRAY=OFF
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
        -DCOMPILER_RT_BUILD_PROFILE=OFF
        -DCOMPILER_RT_BUILD_MEMPROF=OFF
        -DCOMPILER_RT_BUILD_ORC=OFF
        -DCOMPILER_RT_BUILD_GWP_ASAN=OFF
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
        -DCMAKE_C_COMPILER=#{bin}/clang
        -DCMAKE_CXX_COMPILER=#{bin}/clang++
        -DCMAKE_ASM_COMPILER=#{bin}/clang
        -DCMAKE_C_COMPILER_TARGET=#{target_triple}
        -DCMAKE_CXX_COMPILER_TARGET=#{target_triple}
        -DCMAKE_ASM_COMPILER_TARGET=#{target_triple}
        -DCMAKE_AR=#{bin}/llvm-ar
        -DCMAKE_RANLIB=#{bin}/llvm-ranlib
        -DCMAKE_OSX_SYSROOT=#{macos_sdk}
        -DCMAKE_OSX_ARCHITECTURES=#{host_arch}
        -DLLVM_CONFIG_PATH=#{bin}/llvm-config
        -DCMAKE_INSTALL_PREFIX=#{compiler_rt_install_prefix}
      ]

      mkdir buildpath/"compiler-rt/build" do
        system "cmake", "-G", "Ninja", "..", *(std_cmake_args + compiler_rt_args)
        system "cmake", "--build", "."
        system "cmake", "--build", ".", "--target", "install"
      end

      # Move libraries to expected location: lib/clang/<version>/lib/darwin/
      # compiler-rt installs to <prefix>/lib/darwin/, we need lib/clang/<version>/lib/darwin/
      if (compiler_rt_install_prefix/"lib/darwin").exist?
        mkdir_p compiler_rt_install_prefix/"lib"
        # Already in correct place from our install prefix
      elsif (compiler_rt_install_prefix/"darwin").exist?
        # If installed directly to darwin/, move to lib/darwin/
        mkdir_p compiler_rt_install_prefix/"lib"
        mv compiler_rt_install_prefix/"darwin", compiler_rt_install_prefix/"lib/darwin"
      end

      # Install versioned symlink
      lib.install_symlink "libLLVM.dylib" => "libLLVM-#{soversion}.dylib"

      # Install Xcode toolchain
      xctoolchain = prefix/"Toolchains/LLVM#{llvm_version}.xctoolchain"

      system "/usr/libexec/PlistBuddy", "-c", "Add:CFBundleIdentifier string org.llvm.#{llvm_version}", "Info.plist"
      system "/usr/libexec/PlistBuddy", "-c", "Add:CompatibilityVersion integer 2", "Info.plist"
      xctoolchain.install "Info.plist"
      (xctoolchain/"usr").install_symlink [bin, include, lib, libexec, share]
      xctoolchain.parent.install_symlink xctoolchain.basename.to_s => "LLVM#{soversion}.xctoolchain"

      # Write config files for macOS versions
      MacOSVersion::SYMBOLS.each_value do |v|
        macos_version = MacOSVersion.new(v)
        write_config_files(macos_version, MacOSVersion.kernel_major_version(macos_version), Hardware::CPU.arch)
      end
      write_config_files("", "", Hardware::CPU.arch)
    end

    # Install Vim plugins
    %w[ftdetect ftplugin indent syntax].each do |dir|
      (share/"vim/vimfiles"/dir).install Pathname.glob("*/utils/vim/#{dir}/*.vim")
    end

    # Install Emacs modes
    elisp.install llvmpath.glob("utils/emacs/*.el") + share.glob("clang/*.el")
  end

  def write_config_files(macos_version, kernel_version, arch)
    clang_config_file_dir.mkpath

    arches = Set.new([:arm64, :x86_64, :aarch64])
    arches << arch

    sysroot = if macos_version.blank? || MacOS.version > macos_version
      "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX.sdk"
    else
      "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX#{macos_version}.sdk"
    end

    {
      darwin: kernel_version,
      macosx: macos_version,
    }.each do |system, version|
      arches.each do |target_arch|
        config_file = "#{target_arch}-apple-#{system}#{version}.cfg"
        (clang_config_file_dir/config_file).atomic_write <<~CONFIG
          -isysroot #{sysroot}
        CONFIG
      end
    end
  end

  def post_install
    return unless OS.mac?

    config_files = {
      darwin: OS.kernel_version.major,
      macosx: MacOS.version,
    }.map do |system, version|
      clang_config_file_dir/"#{Hardware::CPU.arch}-apple-#{system}#{version}.cfg"
    end
    return if config_files.all?(&:exist?)

    write_config_files(MacOS.version, OS.kernel_version.major, Hardware::CPU.arch)
  end

  def caveats
    <<~EOS
      CLANG_CONFIG_FILE_SYSTEM_DIR: #{clang_config_file_dir}
      CLANG_CONFIG_FILE_USER_DIR:   ~/.config/clang

      This is a custom LLVM HEAD formula that disables compiler-rt to avoid
      the dual sysroot bug on macOS betas. Sanitizers and fuzzer are not
      available in this build.

      This formula includes LLD (the LLVM linker). Available commands:
        ld.lld    - ELF linker
        ld64.lld  - Mach-O linker (macOS)
        lld-link  - COFF linker (Windows)
        wasm-ld   - WebAssembly linker

      To use the bundled libunwind please use the following LDFLAGS:
        LDFLAGS="-L#{opt_lib}/unwind -lunwind"

      To use the bundled libc++ please use the following LDFLAGS:
        LDFLAGS="-L#{opt_lib}/c++ -L#{opt_lib}/unwind -lunwind"
    EOS
  end

  test do
    llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
    assert_equal prefix.to_s, shell_output("#{bin}/llvm-config --prefix").chomp

    (testpath/"test.cpp").write <<~CPP
      #include <iostream>
      int main() {
        std::cout << "Hello World!" << std::endl;
        return 0;
      }
    CPP

    system bin/"clang++", "-v", "-std=c++11", "test.cpp", "-o", "test++"
    assert_equal "Hello World!", shell_output("./test++").chomp
  end
end
