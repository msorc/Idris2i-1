{ stdenv, lib, chez, clang, gmp, makeWrapper, installShellFiles, support, idris2Version
, srcRev, gambit, nodejs, zsh, idris2Bootstrap ? null }:

# Without idris2Bootstrap, bootstraps idris2 with Chez Scheme (`make
# bootstrap`): the compiler is a Chez program.  With idris2Bootstrap (such a
# compiler), builds idris2 like a plain `make` does: with the RefC backend,
# the default code generator, which makes the compiler a native executable,
# build/exec/idris2_app/idris2 next to a launcher script.
let
  bootstrap = idris2Bootstrap == null;
  codegen = if bootstrap then "chez" else "refc";
  supportLibrariesPath = lib.makeLibraryPath [ support ];
  supportSharePath = lib.makeSearchPath "share" [ support ];
  gmpInclude = "${lib.getDev gmp}/include";
  gmpLib = "${lib.getLib gmp}/lib";
  cCompiler = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc";
in
stdenv.mkDerivation rec {
  pname = "idris2";
  version = idris2Version;

  # we don't rebuild Idris when changing the buildIdris nix
  # function:
  src = with lib.fileset; toSource {
    root = ../.;
    fileset = difference ../. ../nix/buildIdris.nix;
  };

  strictDeps = true;
  nativeBuildInputs = [ makeWrapper installShellFiles clang chez ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ zsh ]
    ++ lib.optionals (!bootstrap) [ idris2Bootstrap ];
  buildInputs = [ chez gmp support ];

  # For bootstrap builds the Makefile will try to
  # rebuild the support library if we don't patch
  # bootstrap-install.
  prePatch = ''
    patchShebangs --build tests
    substituteInPlace Makefile \
      --replace-fail '$(GIT_SHA1)' '${srcRev}'
  '' + lib.optionalString bootstrap ''
    substituteInPlace Makefile \
      --replace-fail 'bootstrap-install: install-idris2 install-support' 'bootstrap-install: install-idris2'
  '';

  makeFlags = [
    "IDRIS2_SUPPORT_DIR=${supportLibrariesPath}"
    "IDRIS2_CG=${codegen}"
  ] ++ lib.optional stdenv.hostPlatform.isDarwin "OS=";

  # The name of the main executable of pkgs.chez is `scheme`
  buildFlags = [ "PREFIX=$(out)" ] ++
    lib.optional bootstrap [
      "bootstrap" "SCHEME=scheme"
      "IDRIS2_DATA=${supportSharePath}"
      "IDRIS2_LIBS=${supportLibrariesPath}"
    ];

  # checks happen against built compiler prior to the postInstall
  # wrapper below so we must augment some paths to point at prebuilt
  # support paths regardless of whether we are bootstrapping or not.
  checkInputs = [ gambit nodejs ]; # racket ];
  checkFlags = [
    "INTERACTIVE="
    "IDRIS2_DATA=${supportSharePath}"
    "IDRIS2_LIBS=${supportLibrariesPath}"
    "TEST_IDRIS2_DATA=${supportSharePath}"
    "TEST_IDRIS2_LIBS=${supportLibrariesPath}"
    "TEST_IDRIS2_SUPPORT_DIR=${supportLibrariesPath}"
  ];

  installTargets = "install-idris2 install-with-src-libs";
  installFlags = [ "PREFIX=$(out)" ];

  # TODO: Move this into its own derivation, such that this can be changed
  #       without having to recompile idris2 every time.
  postInstall = let
    name = "${pname}-${version}";
    globalLibraries = [
      "\\$HOME/.nix-profile/lib/${name}"
      "/run/current-system/sw/lib/${name}"
      "$out/${name}"
    ];
    globalLibrariesPath = builtins.concatStringsSep ":" globalLibraries;
    # Whatever built it, the compiler uses the RefC backend unless told
    # otherwise (IDRIS2_CG, --cg), so it needs a C compiler and GMP to
    # compile programs: the C compiler of the user (IDRIS2_CC, CC) comes
    # first, else the one of stdenv, and GMP is added to the flags that the
    # compiler would use otherwise (IDRIS2_CPPFLAGS or CPPFLAGS, and
    # IDRIS2_LDFLAGS or LDFLAGS).  CHEZ is set for `--cg chez`.
    # idris2 installs packages with --install into the path given by
    # IDRIS2_PREFIX. We set that to a default of ~/.idris2, to mirror the
    # behaviour of the standard Makefile install.
    wrapperArgs = ''
      --set-default CHEZ "${chez}/bin/scheme" \
      --run 'export IDRIS2_CC="''${IDRIS2_CC:-''${CC:-${cCompiler}}}"' \
      --run 'export IDRIS2_CPPFLAGS="''${IDRIS2_CPPFLAGS-''${CPPFLAGS-}} -I${gmpInclude}"' \
      --run 'export IDRIS2_LDFLAGS="''${IDRIS2_LDFLAGS-''${LDFLAGS-}} -L${gmpLib} -Wl,-rpath,${gmpLib}"' \
      --run 'export IDRIS2_PREFIX=''${IDRIS2_PREFIX-"$HOME/.idris2"}' \
      --suffix IDRIS2_LIBS ':' "${supportLibrariesPath}" \
      --suffix IDRIS2_DATA ':' "${supportSharePath}" \
      --suffix IDRIS2_PACKAGE_PATH ':' "${globalLibrariesPath}" \
      --suffix LD_LIBRARY_PATH ':' "${supportLibrariesPath}" \
      --suffix DYLD_LIBRARY_PATH ':' "${supportLibrariesPath}"
    '';
  in (if bootstrap then ''
    # Remove existing idris2 wrapper that sets incorrect LD_LIBRARY_PATH
    rm $out/bin/idris2

    # The only thing we need from idris2_app is the actual binary
    mv $out/bin/idris2_app/idris2.so $out/bin/idris2
    rm $out/bin/idris2_app/*
    rmdir $out/bin/idris2_app

    wrapProgram "$out/bin/idris2" \
      ${wrapperArgs}
  '' else ''
    # The RefC build: the compiler is $out/bin/idris2_app/idris2 (with
    # libidris2_support, that the Chez backend copies next to the programs
    # it builds), and $out/bin/idris2 the launcher of bootstrap/idris2-refc.sh,
    # replaced by a wrapper that does what it does: lift the stack limit (the
    # compiler recurses deeply, on the stack of the process with RefC).
    rm $out/bin/idris2
    makeWrapper "$out/bin/idris2_app/idris2" "$out/bin/idris2" \
      --run 'ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -H -s)" 2>/dev/null || true' \
      ${wrapperArgs}
  '') + ''

    installShellCompletion --cmd idris2 \
      --bash <($out/bin/idris2 --bash-completion-script idris2) \
      --zsh <($out/bin/idris2 --zsh-completion-script idris2) \
  '';
}
