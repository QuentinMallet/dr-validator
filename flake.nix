{
  description = "dr-validator — DR test automation tool (umbrella Elixir app)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Elixir 1.18 + Erlang 27 — pinned minor version for reproducibility
        # Note: elixir_1_17 is incompatible with Hex 2.4.0 (nixpkgs ships 2.4.0 for all
        # beam package sets as of this nixpkgs rev); use 1.18 which is the native pairing.
        beamPackages = pkgs.beam.packages.erlang_27;
        elixir = beamPackages.elixir_1_18;
        erlang = beamPackages.erlang;

        hasMixNix = builtins.pathExists ./mix.nix;

        omcSrc =
          if builtins.pathExists ./.omc then
            builtins.path {
              path = ./.omc;
              name = "omc-planning-artifacts";
              filter =
                path: _type:
                let
                  rel = pkgs.lib.removePrefix (toString ./.omc + "/") path;
                in
                pkgs.lib.hasPrefix "plans/" rel
                || pkgs.lib.hasPrefix "specs/" rel
                || pkgs.lib.hasPrefix "research/" rel
                || rel == "";
            }
          else
            null;

        mkGuideDocs =
          { includePlanning ? false }:
          pkgs.stdenv.mkDerivation {
            name = "dr-validator-guide";
            src = ./docs;
            nativeBuildInputs = [ pkgs.mdbook ];
            buildPhase = ''
              cp -r $src build-docs
              chmod -R u+w build-docs
              cd build-docs
              ${pkgs.lib.optionalString (includePlanning && omcSrc != null) ''
                bash scripts/generate-planning-artifacts.sh ${omcSrc} src
              ''}
              mdbook build --dest-dir $out
            '';
            dontInstall = true;
          };

        generateMixNixScript = pkgs.writeShellScriptBin "generate-mix-nix" ''
          if [ ! -f mix.lock ]; then
            echo "Error: mix.lock not found. Run 'mix deps.get' first."
            exit 1
          fi
          echo "Generating mix.nix from mix.lock..."
          ${pkgs.mix2nix}/bin/mix2nix > mix.nix
          echo "Generated mix.nix. Commit it, then 'nix build'."
        '';

      in
      {
        packages =
          {
            doc = mkGuideDocs { };
            doc-with-planning = mkGuideDocs { includePlanning = true; };
            generate-mix-nix = generateMixNixScript;
          }
          // pkgs.lib.optionalAttrs hasMixNix {
            default =
              let
                mixNixDeps = import ./mix.nix { inherit (pkgs) lib; inherit beamPackages; };
              in
              (beamPackages.mixRelease {
                pname = "dr-validator";
                version = "0.1.0";
                src = ./.;
                mixEnv = "prod";
                inherit mixNixDeps;
                meta = with pkgs.lib; {
                  description = "DR test automation tool";
                  platforms = platforms.unix;
                };
              }).overrideAttrs (_old: {
                # Build the umbrella OTP release (includes both dr_validator and
                # dr_validator_openbao sub-apps per the releases config in mix.exs).
                # The escript distribution model was dropped because escript bundles
                # only the sub-app it is built from, silently omitting sibling apps.
                buildPhase = ''
                  runHook preBuild
                  mix compile --no-deps-check
                  runHook postBuild
                '';
                installPhase = ''
                  runHook preInstall
                  # --no-compile: deps are already compiled by the Nix configurePhase
                  # (pre-built rebar3/mix packages symlinked into _build/prod/lib/).
                  # Without this flag, `mix release` would invoke rebar3 to recompile
                  # rebar3 deps (e.g. unicode_util_compat) — rebar3 then fails trying
                  # to store its compilation DAG inside the read-only Nix store.
                  mix release dr_validator --path "$out" --overwrite --no-compile
                  # One-shot CLI wrapper: evaluates DrValidator.EscriptMain.main/1
                  # inside the release node, propagating the integer exit code via
                  # System.halt/1. System.argv() inside `eval` receives the args
                  # passed after the "--" separator.
                  cat > "$out/bin/dr-validator-run" <<'WRAPPER'
                  #!/usr/bin/env bash
                  exec "$(dirname "$0")/dr_validator" eval "DrValidator.EscriptMain.main(System.argv())" -- "$@"
                  WRAPPER
                  chmod +x "$out/bin/dr-validator-run"
                  runHook postInstall
                '';
                # Clear postFixup — default mixRelease postFixup rewraps bin/ scripts
                # with env-var injection we do not need for a self-contained release.
                postFixup = "";
              });
          };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            elixir
            erlang
            beamPackages.hex
            beamPackages.rebar3
            pkgs.mix2nix
            beamPackages.elixir-ls
            pkgs.git
            pkgs.inotify-tools
            # Local dev: secrets vault + OIDC provider
            pkgs.openbao
            pkgs.dex
            # Browser-driven tests (Wallaby)
            pkgs.chromium
            pkgs.chromedriver
          ];

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            mkdir -p "$MIX_HOME" "$HEX_HOME"
            export PATH="$MIX_HOME/bin:$HEX_HOME/bin:$PATH"
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8
            export BAO_ADDR="''${BAO_ADDR:-http://127.0.0.1:8200}"

            if [ ! -f .dev/dex.yaml ]; then
              mkdir -p .dev
              cat > .dev/dex.yaml.tmp <<'DEX_EOF'
            issuer: http://127.0.0.1:5556/dex
            storage:
              type: memory
            web:
              http: 127.0.0.1:5556
            staticClients:
              - id: dev-client
                redirectURIs:
                  - http://127.0.0.1:8080/callback
                name: Dev Client
                secret: dev-secret
            enablePasswordDB: true
            staticPasswords:
              - email: admin@example.com
                hash: "$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"
                username: admin
                userID: 08a8684b-db88-4b73-90a9-3cd1661f5466
            DEX_EOF
              mv .dev/dex.yaml.tmp .dev/dex.yaml
            fi

            echo "dr-validator dev shell"
            echo "  Elixir $(elixir --version 2>/dev/null | head -1 | awk '{print $2}') / Erlang/OTP $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null)"
            echo "  bao server -dev          # OpenBao on :8200"
            echo "  dex serve .dev/dex.yaml  # Dex OIDC on :5556"
          '';
        };

        apps.generate-mix-nix = flake-utils.lib.mkApp {
          drv = generateMixNixScript;
        };
      }
    );
}
