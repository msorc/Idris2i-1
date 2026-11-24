{
  description = "Idris2i-1 flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.idris-emacs-src = {
    url = "github:idris-community/idris2-mode";
    flake = false;
  };
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs = { self, nixpkgs, flake-utils, idris-emacs-src }:
    let
      idris2i_1Version = "0.1.0";
      lib = import ./nix/lib.nix;
      sys-agnostic = rec {
        templates.pkg = {
          path = ./nix/templates/pkg;
          description = "A custom Idris2i-1 package";
        };
        templates.pkgWithDeps = {
          path = ./nix/templates/pkgWithDeps;
          description = "A custom Idris2i-1 package with dependencies";
        };
        defaultTemplate = templates.pkg;
        version = idris2i_1Version;
        overlays.default = final: prev:
          let
            outputPackages = prev.lib.filterAttrs
              (n: _: n != "default" && n != "idris2i_1Api")
              self.packages.${prev.system};
            idris2i_1Api = final.callPackage ./nix/idris2i_1Api.nix {
              inherit (final.idris2i_1Packages) buildIdris;
              inherit idris2i_1Version;
            };
          in
           {
             idris2i_1Packages = prev.idris2i_1Packages // outputPackages // { inherit idris2i_1Api; };
             idris2i-1 = final.idris2i_1Packages.idris2i-1;
           };
      };
      per-system = { config ? { }, overlays ? [ ] }:
        system:
        let
          pkgs = import nixpkgs { inherit config system overlays; };
          chezSupportsSystem = (system == "x86_64-linux")
            || (pkgs.lib.versionAtLeast pkgs.chez.version "10.0.0");
          chez = if chezSupportsSystem then
            pkgs.chez
          else
            pkgs.chez-racket;
          idris2i_1Support = pkgs.callPackage ./nix/support.nix { inherit idris2i_1Version; };
          idris2i_1Bootstrap = pkgs.callPackage ./nix/package.nix {
            inherit idris2i_1Version chez;
            idris2i_1Bootstrap = null;
            support = idris2i_1Support;
            srcRev = self.shortRev or "dirty";
          };
          idris2i_1Pkg = pkgs.callPackage ./nix/package.nix {
            inherit idris2i_1Version chez idris2i_1Bootstrap;
            support = idris2i_1Support;
            srcRev = self.shortRev or "dirty";
          };
          buildIdris = pkgs.callPackage ./nix/buildIdris.nix {
            inherit idris2i_1Version;
            idris2i-1 = idris2i_1Pkg;
            support = idris2i_1Support;
          };
          idris2i_1ApiPkg = pkgs.callPackage ./nix/idris2i_1Api.nix {
            inherit idris2i_1Version buildIdris;
          };
        in {
          checks = import ./nix/test.nix {
            inherit (pkgs) system stdenv runCommand lib;
            inherit nixpkgs flake-utils;
            idris = self;
          };
          packages = rec {
            support = idris2i_1Support;
            idris2i-1 = idris2i_1Pkg;
            idris2i_1Api = idris2i_1ApiPkg.library { withSource = true; };
            default = idris2i-1;
          } // (import ./nix/text-editor.nix {
            inherit pkgs idris-emacs-src idris2i_1Pkg;
          });
          inherit buildIdris;
          devShells.default = pkgs.mkShell{
            packages = idris2i_1Pkg.buildInputs;
          };
        };
    in lib.mkOvrOptsFlake
    (opts: flake-utils.lib.eachDefaultSystem (per-system opts) // sys-agnostic);
}
