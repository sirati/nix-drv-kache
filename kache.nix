{
  lib,
  rustPlatform,
  fetchCrate,
  # Pinned rather than tracking latest: this package is consumed as a
  # RUSTC_WRAPPER, so it sits in front of every rustc invocation in a dev shell
  # and its blast radius is the whole workspace. Upstream ships release
  # candidates on `main` (0.15.0-rc.1 at the time of writing); a shared dev
  # shell should be on the stable line.
  version ? "0.14.2",
  hash ? "sha256-zjS29Mm837F2O/Dji0u0k0bAgz3iAAc5vXvkD4j2V2Q=",
  cargoHash ? "sha256-OxCLKigqys5dRJc8drDqsxIZRGQvlZeFk4Cv/PpwZxk=",
}:
rustPlatform.buildRustPackage {
  pname = "kache";
  inherit version cargoHash;

  src = fetchCrate {
    pname = "kache";
    inherit version hash;
  };

  # Upstream's suite wants a writable store and a running daemon, neither of
  # which exists in the build sandbox.
  doCheck = false;

  meta = with lib; {
    description = "Zero-copy, content-addressed build cache for Rust and C/C++";
    longDescription = ''
      A drop-in RUSTC_WRAPPER (and cc/c++ wrapper) that keys artifacts by a
      blake3 hash of normalized compiler inputs. Cache hits are restored
      zero-copy where the filesystem allows one -- a reflink on btrfs, XFS with
      reflink, or APFS -- and fall back to a hardlink or a copy elsewhere.
      Identical blobs are stored once and linked many times, so a cache hit
      costs almost no additional disk.
    '';
    homepage = "https://github.com/kunobi-ninja/kache";
    license = licenses.asl20;
    mainProgram = "kache";
    platforms = platforms.unix;
  };
}
