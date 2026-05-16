# homebrew-unhosted

Homebrew tap for [unhosted](https://github.com/unhosted-ai/unhosted-core) dependencies that aren't shipped by upstream Homebrew the way unhosted needs them.

Today: one formula, `llama-cpp-rpc` — `llama.cpp` built with `-DGGML_RPC=ON`, which the [unhosted VRAM-pooling feature](https://github.com/unhosted-ai/unhosted-core/blob/main/design/0009-vram-pooling.md) requires. Upstream `brew install llama.cpp` omits the flag, so `llama-server` ships without `--rpc` support and `rpc-server` isn't built at all.

## Install

```sh
brew tap unhosted-ai/unhosted
brew install unhosted-ai/unhosted/llama-cpp-rpc
```

Verify:

```sh
llama-server --help | grep -- --rpc   # should print "--rpc <SERVERS>..."
which rpc-server                       # should print a path
```

Then point unhosted at your llama.cpp install and `unhosted vram-pool detect` will report `ready for pool: YES`.

## Coexistence with upstream `llama.cpp`

This formula installs symlinks at `llama-server-rpc` and `rpc-server-llama` in addition to the standard `llama-server` and `rpc-server` names, so it can be installed alongside the upstream `brew install llama.cpp` without PATH-order surprises. Users who don't have the upstream formula installed can use either name interchangeably.

## When this tap goes away

The plan is to deprecate this tap once homebrew-core adds `-DGGML_RPC=ON` to the upstream `llama.cpp` formula. Tracking issue: [TBD — link here once filed]. Until then, this tap is the canonical install path for RPC-enabled llama.cpp on macOS.

## License

The formula itself is MIT. llama.cpp itself is also MIT — see the upstream repo.
