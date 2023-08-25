{neovim-input}: final: prev:
with prev.haskell.lib;
with prev.lib; let
  haskellPackages = prev.haskellPackages.override (old: {
    overrides = prev.lib.composeExtensions (old.overrides or (_: _: {})) (
      self: super: let
        neoluaPkg = buildFromSdist (
          overrideCabal (super.callPackage ../neolua/default.nix {})
          (old: {
            configureFlags =
              (old.configureFlags or [])
              ++ [
                "--ghc-options=-O2"
                "--ghc-options=-j"
                "--ghc-options=+RTS"
                "--ghc-options=-A256m"
                "--ghc-options=-n4m"
                "--ghc-options=-RTS"
                "--ghc-options=-Wall"
                "--ghc-options=-Werror"
                "--ghc-options=-Wincomplete-uni-patterns"
                "--ghc-options=-Wincomplete-record-updates"
                "--ghc-options=-Wpartial-fields"
                "--ghc-options=-Widentities"
                "--ghc-options=-Wredundant-constraints"
                "--ghc-options=-Wcpp-undef"
                "--ghc-options=-Wunused-packages"
                "--ghc-options=-Wno-deprecations"
              ];
          })
        );
        neolua-bin = prev.haskellPackages.generateOptparseApplicativeCompletions ["neolua"] neoluaPkg;
      in {
        inherit neolua-bin;
      }
    );
  });

  neovim-nightly = neovim-input.packages.${prev.system}.neovim;

  mkNeoluaWrapper = name: neovim:
    prev.pkgs.writeShellApplication {
      inherit name;
      checkPhase = "";
      runtimeInputs = [
        haskellPackages.neolua-bin
        neovim
      ];
      text = ''
        neolua "$@";
      '';
    };

  neolua-stable-wrapper = mkNeoluaWrapper "neolua" prev.pkgs.neovim-unwrapped;

  neolua-nightly-wrapper = mkNeoluaWrapper "neolua-nightly" neovim-nightly;

  luajit =
    (prev.pkgs.luajit.overrideAttrs (old: {
      postInstall = ''
        ${old.postInstall}
        ln -s ${neolua-stable-wrapper}/bin/neolua $out/bin/neolua
        ln -s ${neolua-nightly-wrapper}/bin/neolua-nightly $out/bin/neolua-nightly
      '';
    }))
    .override {
      self = luajit;
    };

  mkNeorocks = neolua-pkgs:
    prev.pkgs.symlinkJoin {
      name = "neorocks";
      paths =
        [
          final.luajit
          final.luajitPackages.luarocks
        ]
        ++ neolua-pkgs;
    };

  neorocks = mkNeorocks [
    neolua-stable-wrapper
    neolua-nightly-wrapper
  ];

  neorocksTest = {
    src,
    name,
    neovim ? neovim-nightly,
    version ? "scm-1",
    luaPackages ? [], # e.g. p: with p; [plenary.nvim]
    extraPackages ? [], # Extra dependencies
  }: let
    neolua-wrapper = mkNeoluaWrapper "neolua" neovim;

    luajit = prev.pkgs.luajit;

    busted = luajit.pkgs.busted.overrideAttrs (oa: {
      postInstall = ''
        ${oa.postInstall}
        substituteInPlace ''$out/bin/busted \
          --replace "${luajit}/bin/luajit" "${neolua-wrapper}/bin/neolua"
      '';
    });
  in (luajit.pkgs.buildLuarocksPackage {
    inherit src version;
    pname = name;
    propagatedBuildInputs =
      [
        busted
      ]
      ++ luaPackages luajit.pkgs;
    doCheck = true;
    nativeCheckInputs = extraPackages;
  });
in {
  inherit
    haskellPackages
    neorocks
    neorocksTest
    neovim-nightly
    ;
  luajitPackages = luajit.pkgs;
}
