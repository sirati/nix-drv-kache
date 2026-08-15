# nix-drv-kache

A nix package, overlay and dev-shell primitives for
[kache](https://github.com/kunobi-ninja/kache) — a content-addressed build
cache for Rust and C/C++, and a drop-in `RUSTC_WRAPPER`.

kache is not in nixpkgs, so this builds it from the crate.

## Why the primitives exist

Packaging kache is the easy half. Two things decide whether it caches anything
at all, and both fail *silently*:

1. **Nothing sets `RUSTC_WRAPPER`.** A `kache` on `PATH` and nothing else
   caches exactly zero compiles. (This is not hypothetical — it is how an
   sccache entry sat inert in a dev shell here for months.)
2. **The store is on a different filesystem from `target/`.** A reflink cannot
   cross a filesystem, so every "zero-copy" restore silently becomes a full
   copy. kache's own default store, `~/.cache/kache`, is exactly this mistake
   on any machine whose checkouts do not live under `$HOME` — and it reports no
   error, it just uses the disk you were trying to save.

`lib.withKache` gets both right in one line.

## Use

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    kache = {
      url = "github:sirati/nix-drv-kache";
      # build against your nixpkgs, not a second copy
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, kache, ... }: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ kache.overlays.default ];
    };
  in {
    devShells.x86_64-linux.default = pkgs.mkShell (kache.lib.withKache
      { inherit (pkgs) kache; }
      {
        packages = [ pkgs.cargo pkgs.rustc ];
      });
  };
}
```

Then add to `.gitignore` (also available as `kache.lib.gitignoreLines`):

```
/.kache.toml
/.kache-store/
```

## Store location

By default the store is `.kache-store` at **the root of the dev shell** — the
directory `nix develop` / `nix-shell` was invoked from. That keeps it on the
same filesystem as `target/` by construction, which is what makes restores
reflinks instead of copies.

It is deliberately *not* inferred by walking the filesystem. Override it either
way:

- at eval time: `withKache { inherit (pkgs) kache; storeDir = "/data/me/kache"; }`
- at runtime: `export KACHE_STORE_DIR=/data/me/kache`

The default is per-checkout, so two worktrees keep two stores and do not share
compiled artifacts with each other. Pointing several checkouts at one store
trades that back — keep it on the same filesystem as all of them, or the
reflinks are lost.

## API

| Attribute | What it is |
|---|---|
| `overlays.default` | adds `pkgs.kache` |
| `packages.<system>.kache` | the package itself |
| `lib.withKache` | merge kache into an existing `mkShell` argument set |
| `lib.mkKacheShellParts` | the raw `{ packages, env, shellHook }` |
| `lib.mkKacheShellHook` | just the hook that writes `.kache.toml` |
| `lib.mkKacheConfig` | just the config rendering |
| `lib.defaultStoreExpr` | the shell expression the store resolves through |
| `lib.gitignoreLines` | what a consumer should ignore |

`withKache` / `mkKacheShellParts` / `mkKacheShellHook` accept:

| Argument | Default | Meaning |
|---|---|---|
| `kache` | — | the package (required by `withKache`, `mkKacheShellParts`) |
| `storeDir` | `null` | absolute path; `null` uses `defaultStoreExpr` |
| `configFile` | `.kache.toml` | written at the shell root |
| `localOnly` | `true` | no remote or planner egress |
| `storageLayoutAdvice` | `true` | warn if a restore falls back to copying |
| `maxSize` | `null` | e.g. `"200GiB"`; `null` leaves kache's default |
| `extraSettings` | `{}` | extra `[cache]` keys as rendered TOML values |

## Measuring whether it works

Two counters look authoritative and are not:

- **`kache stats` read just after a cold daemon start** reports a fraction of
  what happened. It showed 12 operations where 161 had occurred.
- **`events.jsonl` is sampled**, not one line per compile — 8 lines for 161
  compiles.

Neither is a coverage metric. Count wrapper invocations instead (point
`RUSTC_WRAPPER` at a shim that logs and then `exec`s kache), or time a
genuinely cold rebuild. On a reflink-capable filesystem the honest check is the
byte counters on restore: `reflinked_bytes` should be large and `copied_bytes`
zero.
