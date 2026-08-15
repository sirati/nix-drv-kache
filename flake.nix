{
  description = "kache — content-addressed Rust build cache: package, overlay and dev-shell primitives";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    {
      # `pkgs.kache` in any project that imports this.
      overlays.default = final: _prev: {
        kache = final.callPackage ./kache.nix {};
      };

      # System-independent primitives. See lib.nix for what each one is for.
      lib = import ./lib.nix {inherit (nixpkgs) lib;};

      # A consuming flake's whole integration, for reference:
      #
      #   inputs.kache.url = "github:sirati/nix-drv-kache";
      #   ...
      #   pkgs = import nixpkgs {
      #     inherit system;
      #     overlays = [ kache.overlays.default ];
      #   };
      #   devShells.default = pkgs.mkShell (kache.lib.withKache
      #     { inherit (pkgs) kache; }
      #     { packages = [ ... ]; });
      #
      # then add kache.lib.gitignoreLines to .gitignore.
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [self.overlays.default];
      };
    in {
      packages = {
        inherit (pkgs) kache;
        default = pkgs.kache;
      };

      # Dogfood: this shell wires kache into itself.
      devShells.default = pkgs.mkShell (self.lib.withKache
        {inherit (pkgs) kache;}
        {
          packages = [pkgs.alejandra];
        });

      formatter = pkgs.alejandra;
    });
}
