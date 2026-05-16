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

  # Keep the keg unlinked at the standard names because they conflict
  # with the upstream `llama.cpp` formula. Users typically have both
  # installed (upstream for general use, this for VRAM-pooling), so we
  # surface our binaries via distinct names — see `install` below.
  keg_only :versioned_formula

  def install
    args = std_cmake_args + %W[
      -DBUILD_SHARED_LIBS=ON
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DLLAMA_ALL_WARNINGS=OFF
      -DLLAMA_BUILD_TESTS=OFF
      -DGGML_RPC=ON
    ]
    # Apple Silicon: assert Metal explicitly. Upstream defaults to ON
    # on macOS, but pinning it here protects against a future config
    # change silently producing a CPU-only build that would be slow
    # and indistinguishable from a working install.
    args << "-DGGML_METAL=ON" if OS.mac?

    system "cmake", "-S", ".", "-B", "build", *args
    system "cmake", "--build", "build", "--config", "Release"
    system "cmake", "--install", "build", "--config", "Release", "--prefix", prefix

    # Coexist with the upstream `llama.cpp` formula. The standard
    # binary names (`llama-server`, `rpc-server`) stay inside the keg
    # via `keg_only`; here we expose distinctly-named symlinks on
    # PATH so users with BOTH formulas installed don't get PATH-order
    # surprises. unhosted's `vram_pool::probe` looks for both names.
    HOMEBREW_PREFIX.install_symlink bin/"llama-server" => "bin/llama-server-rpc"
    if (bin/"rpc-server").exist?
      HOMEBREW_PREFIX.install_symlink bin/"rpc-server" => "bin/rpc-server"
    end
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
