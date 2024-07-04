{
  description = "nodecg";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nodecg-cli-src = {
      url = "github:nodecg/nodecg-cli";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nodecg-cli-src, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      forAllSystems = f:
        lib.genAttrs lib.systems.flakeExposed (system:
          f (import nixpkgs {
            inherit system;
          }));
    in
    {
      overlays.default = final: prev: rec {
        nodecg-cli = with final; stdenv.mkDerivation rec {
          pname = "nodecg-cli";
          version = nodecg-cli-src.shortRev or nodecg-cli-src.dirtyShortRev or nodecg-cli-src.lastModified or "unknown";
          src = nodecg-cli-src;

          npmDeps = fetchNpmDeps {
            inherit src;
            hash = "sha256-GgS3Gq++9P0/cXl5ur0q8KC/ComZVWVulQGtVd99ELg=";
          };

          npmBuildScript = "build";

          nativeBuildInputs = [
            nodejs
            npmHooks.npmConfigHook
            npmHooks.npmInstallHook
            npmHooks.npmBuildHook
          ];

          meta = {
            mainProgram = "nodecg";
          };
        };
        nodecg-server =
          with final; stdenv.mkDerivation rec {
            pname = "nodecg-server";
            version = self.shortRev or self.dirtyShortRev or self.lastModified or "unknown";
            src = self;

            npmDeps = fetchNpmDeps {
              inherit src;
              hash = "sha256-9f95hcnxfeKJp8rBBeULBeYf49mkzTUXMTC60cCX0TU=";
            };

            env = {
              PUPPETEER_SKIP_DOWNLOAD = true;
            };

            makeCacheWritable = true;
            nativeBuildInputs = [
              nodejs
              python3
              npmHooks.npmConfigHook
              npmHooks.npmInstallHook
              makeWrapper
              breakpointHook
            ];

            postInstall = ''
              makeWrapper ${lib.getExe nodejs} $out/bin/nodecg-server \
                --add-flags $out/lib/node_modules/nodecg/index.js \
                --run 'export NODECG_ROOT=''${NODECG_ROOT-''${XDG_STATE_DIR-~/.local/state}/nodecg}; mkdir -p $NODECG_ROOT'
            '';

            buildPhase =
              let
                typesCache = pkgs.fetchNpmDeps {
                  src = "${self}/generated-types";
                  hash = "sha256-i0+dE2ZYlAhBIRHO3oqtNq/EIb29WZoio3rN//whfIk=";
                };
              in
              ''
                npm run build:tsc
                npm run build:client
                npm run build:copy-templates
                pushd generated-types
                npm ci --cache ${typesCache}
                patchShebangs node_modules
                npx tsc
                popd
              '';

            meta = {
              mainProgram = "nodecg-server";
            };
          };
      };
      packages = forAllSystems (pkgs: self.overlays.default pkgs pkgs);
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell (with self.packages.${pkgs.system}; {
          buildInputs = [
            nodecg-cli
            nodecg-server
          ];
        });
      });
      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
