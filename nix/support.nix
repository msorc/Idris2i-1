{ stdenv, lib, gmp, idris2i_1Version }:
stdenv.mkDerivation rec {
  pname = "libidris2i_1_support";
  version = idris2i_1Version;

  # we don't rebuild Idris when changing the buildIdris nix
  # function:
  src = with lib.fileset; toSource {
    root = ../.;
    fileset = difference ../. ../nix/buildIdris.nix;
  };

  strictDeps = true;
  buildInputs = [ gmp ];

  makeFlags = [
    "PREFIX=$(out)"
  ] ++ lib.optional stdenv.hostPlatform.isDarwin "OS=";

  buildFlags = [ "support" ];

  installTargets = "install-support";

  postInstall = ''
    mv $out/idris2i-1-${version}/lib $out/lib
    mv $out/idris2i-1-${version}/support $out/share
    rmdir $out/idris2i-1-${version}
  '';
}
