{
  description = "Fail-closed GitHub CLI wrapper backed by GNU pass";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          wrapper = pkgs.callPackage ./package.nix { };
        in
        {
          default = wrapper;
          gh-pass-wrapper = wrapper;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          wrapper = import ./tests/wrapper.nix { inherit pkgs; };
        }
      );

      formatter = forAllSystems (system: (mkPkgs system).nixfmt);
    };
}
