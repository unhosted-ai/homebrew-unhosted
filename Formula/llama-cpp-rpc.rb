# Homebrew formula for an RPC-enabled llama.cpp build, intended for
# use with the unhosted daemon's VRAM-pooling feature (ADR 0009).
#
# Upstream `brew install llama.cpp` does NOT pass `-DGGML_RPC=ON`,
# so the resulting `llama-server` lacks the `--rpc` flag and the
# distribution doesn't include `rpc-server` at all. Without those
# two, unhosted's `vram-pool` orchestration has nothing to call.
#
# This formula adds the flag and otherwise mirrors the upstream
# formula's build. Until homebrew-core ships RPC by default — see
# https://github.com/Homebrew/homebrew-core for the pending PR —
# this tap is the canonical install path.
#
# Naming: binaries land at `llama-server-rpc` and `rpc-server-llama`
# so this formula coexists with the upstream `llama.cpp` without
# PATH-order surprises. unhosted's `vram_pool::probe` looks for
# `rpc-server` directly (the standard name) AND for `--rpc` in
# `llama-server --help`, so once a user has either build available
# the capability check passes.

class LlamaCppRpc < Formula
  desc "Inference of LLMs in pure C/C++ — RPC-enabled build for unhosted VRAM-pooling"
  homepage "https://github.com/ggerganov/llama.cpp"
  url "https://github.com/ggerganov/llama.cpp/archive/refs/tags/b9090.tar.gz"
  sha256 "e6abe9c2d2711b8b0daa8b33b26c804870e128e1ad8d636aa3e53d5c30ab791d"
  license "MIT"
  head "https://github.com/ggerganov/llama.cpp.git", branch: "master"

  depends_on "cmake" => :build
  depends_on "curl"

  # Live entirely inside the keg. The lib/* and include/* files
  # collide with the upstream `ggml` and `llama.cpp` formulas
  # (which is how llama-server links). The binaries link to libs
  # via rpath, so as long as the keg's own lib/ is reachable they
  # work fine from the opt-prefix path. unhosted's `vram_pool::probe`
  # knows to look at `#{HOMEBREW_PREFIX}/opt/llama-cpp-rpc/bin/`
  # directly, so the user doesn't have to touch PATH for VRAM-pooling
  # to work.
  keg_only :versioned_formula

  def install
    args = std_cmake_args + %W[
      -DBUILD_SHARED_LIBS=ON
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DLLAMA_ALL_WARNINGS=OFF
      -DLLAMA_BUILD_TESTS=OFF
      -DGGML_RPC=ON
      -DGGML_BLAS=OFF
    ]
    # GGML_BLAS=OFF works around an upstream bug in llama.cpp b9090:
    # when `rpc-server` receives a graph compute request that
    # includes RMS_NORM and BLAS is the assigned backend for it,
    # rpc-server aborts with "ggml_backend_blas_graph_compute:
    # unsupported op RMS_NORM" and llama-server reports "Remote RPC
    # server crashed or returned malformed response" within 2-3 s of
    # the first inference. Disabling BLAS routes the op through CPU
    # / Metal instead and the pool stays up. Tracking upstream for a
    # fix; will re-enable BLAS once the op coverage in the BLAS
    # backend catches up.
    # Apple Silicon: assert Metal explicitly. Upstream defaults to ON
    # on macOS, but pinning it here protects against a future config
    # change silently producing a CPU-only build that would be slow
    # and indistinguishable from a working install.
    args << "-DGGML_METAL=ON" if OS.mac?

    system "cmake", "-S", ".", "-B", "build", *args
    system "cmake", "--build", "build", "--config", "Release"
    system "cmake", "--install", "build", "--config", "Release", "--prefix", prefix

    # Trim the keg down to just the two binaries unhosted needs.
    # Cuts install size and reduces surface that could conflict if a
    # future maintainer drops `keg_only`. The bins still link via
    # rpath to lib/ which we keep intact.
    Dir.glob(bin/"*").each do |file|
      base = File.basename(file)
      next if %w[llama-server rpc-server].include?(base)
      File.delete(file) if File.file?(file)
    end
  end

  def caveats
    <<~EOS
      llama-cpp-rpc is keg-only because its lib/ and include/ files
      collide with the upstream `ggml` and `llama.cpp` formulas. The
      binaries are at:

        #{opt_bin}/llama-server   (RPC-enabled — has --rpc flag)
        #{opt_bin}/rpc-server     (layer-host daemon)

      The unhosted daemon looks for them at exactly that path, so
      `unhosted vram-pool detect` should report `ready for pool: YES`
      after this install with no PATH changes needed.

      To call them directly from your shell, use the absolute paths
      above, or add #{opt_bin} to your PATH.
    EOS
  end

  test do
    # The whole point of this formula: --rpc must be present.
    output = shell_output("#{bin}/llama-server --help 2>&1")
    assert_match "--rpc", output,
      "llama-server build is missing --rpc — -DGGML_RPC=ON did not take effect"

    # rpc-server is what makes a peer a layer host. Bail if missing.
    assert_predicate bin/"rpc-server", :exist?,
      "rpc-server binary not built — check -DGGML_RPC=ON took effect"
  end
end
