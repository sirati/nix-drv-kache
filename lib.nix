# Dev-shell primitives for wiring kache into a project.
#
# The package alone is not enough to cache anything: kache only takes effect
# when something sets RUSTC_WRAPPER, and its store has to land somewhere a
# reflink can reach. Both are easy to leave out, and both fail silently -- a
# missing wrapper caches nothing, a store on the wrong filesystem quietly
# degrades every "zero-copy" restore into a full copy. These helpers exist so a
# project gets both right in one line.
{lib}: rec {
  # The store's default location.
  #
  # A shell expression, not a nix path, and deliberately so: the answer depends
  # on where the dev shell was entered, which nix does not know at eval time.
  # For a flake, `./.` evaluates to a read-only /nix/store copy of the source --
  # exactly the wrong place for a writable cache.
  #
  # Resolution order:
  #   1. $KACHE_STORE_DIR, if the caller exported one
  #   2. `.kache-store` at the root of the shell, i.e. the directory `nix
  #      develop` / `nix-shell` was invoked from
  #
  # This keeps the store on the same filesystem as `target/` by construction,
  # which is the property that makes restores reflinks instead of copies.
  #
  # It is per-checkout: two worktrees get two stores, and so do not share
  # compiled artifacts with each other. Point `storeDir` (or $KACHE_STORE_DIR)
  # at a common directory to trade that back, but keep it on the same
  # filesystem as the checkouts or the reflinks are lost.
  defaultStoreExpr = ''"''${KACHE_STORE_DIR:-$PWD/.kache-store}"'';

  # Render the `[cache]` table of a .kache.toml.
  #
  # `storeExpr` is a shell expression that expands to the store path, so the
  # file can carry a value only known at shell entry.
  mkKacheConfig = {
    storeExpr ? defaultStoreExpr,
    localOnly ? true,
    storageLayoutAdvice ? true,
    maxSize ? null,
    # Extra `[cache]` keys, given as already-rendered TOML values:
    #   { compression_level = "9"; exclude = ''["vendor/**"]''; }
    extraSettings ? {},
  }: let
    bool = b:
      if b
      then "true"
      else "false";
    renderExtra =
      lib.mapAttrsToList (k: v: "printf '%s\\n' '${k} = ${v}'")
      extraSettings;
  in
    lib.concatStringsSep "\n" ([
        "printf '%s\\n' '# Generated on dev-shell entry by kache-nix. Not committed, not hand-edited:'"
        "printf '%s\\n' '# every `nix develop` overwrites it.'"
        "printf '%s\\n' ''"
        "printf '%s\\n' '[cache]'"
        "printf '%s\\n' '# Kept on the same filesystem as the checkout, so a hit restores as a'"
        "printf '%s\\n' '# reflink rather than a copy. A reflink cannot cross a filesystem.'"
        "printf 'local_store = \"%s\"\\n' \"$kacheStore\""
        "printf '%s\\n' 'local_only = ${bool localOnly}'"
        "printf '%s\\n' 'storage_layout_advice = ${bool storageLayoutAdvice}'"
      ]
      ++ lib.optional (maxSize != null)
      "printf '%s\\n' 'local_max_size = \"${maxSize}\"'"
      ++ renderExtra);

  # A shellHook that resolves the store, creates it, and writes the config.
  #
  # printf rather than a heredoc throughout: this string is interpolated into a
  # caller's indented nix string, where a heredoc terminator cannot be relied on
  # to reach column 0.
  mkKacheShellHook = {
    storeDir ? null,
    configFile ? ".kache.toml",
    ...
  } @ args: let
    storeExpr =
      if storeDir != null
      then ''"${storeDir}"''
      else defaultStoreExpr;
    cfg = mkKacheConfig ((builtins.removeAttrs args ["storeDir" "configFile"])
      // {inherit storeExpr;});
  in ''
    kacheStore=${storeExpr}
    mkdir -p "$kacheStore"
    {
    ${cfg}
    } > "$PWD/${configFile}"
  '';

  # The three things a dev shell needs, ready to merge into mkShell.
  #
  # RUSTC_WRAPPER names the store path rather than the bare `kache`, so it still
  # resolves for anything invoking cargo with a trimmed PATH. Measured: `dx`
  # passes this through to cargo, so dioxus builds are cached too.
  mkKacheShellParts = {
    kache,
    ...
  } @ args: {
    packages = [kache];
    env.RUSTC_WRAPPER = "${kache}/bin/kache";
    shellHook = mkKacheShellHook (builtins.removeAttrs args ["kache"]);
  };

  # Merge kache into an existing mkShell argument set, preserving whatever the
  # caller already had in packages / env / shellHook.
  #
  #   pkgs.mkShell (kacheLib.withKache { inherit (pkgs) kache; } {
  #     packages = [ ... ];
  #   })
  withKache = kacheArgs: shellArgs: let
    parts = mkKacheShellParts kacheArgs;
  in
    shellArgs
    // {
      packages = (shellArgs.packages or []) ++ parts.packages;
      env = (shellArgs.env or {}) // parts.env;
      shellHook = (shellArgs.shellHook or "") + "\n" + parts.shellHook;
    };

  # What a consuming project should add to .gitignore.
  gitignoreLines = ''
    /.kache.toml
    /.kache-store/
  '';
}
