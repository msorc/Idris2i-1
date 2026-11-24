{ buildIdris, idris2i_1Version }:
buildIdris {
  src = ./..;
  ipkgName = "idris2i-1-api";
  version = idris2i_1Version;
  idrisLibraries = [ ];
  preBuild = ''
    export IDRIS2I_1_PREFIX=$out/lib
    make src/IdrisPaths.idr
  '';
}
