{
  description = "Nix flake for CLIProxyAPI - AI CLI proxy service";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Supported systems for CLIProxyAPI
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Map Nix system to release asset naming
      systemToAsset = system: {
        "x86_64-linux" = "linux_amd64";
        "aarch64-linux" = "linux_arm64";
        "x86_64-darwin" = "darwin_amd64";
        "aarch64-darwin" = "darwin_arm64";
      }.${system};

      # Edition metadata (updated by GitHub Action per edition)
      editions = {
        cliproxyapi = {
          version = "6.9.2";
          hashes = {
            "x86_64-linux" = "sha256-Zr+7N4Jm2J8Q2ns35CgkiGNPKfYVCsxwtffUIkfNhpE=";
            "aarch64-linux" = "sha256-pZ9CBxZD15VonL7zbqtgGPA/pddAUNzEZxzEuj40M9g=";
            "x86_64-darwin" = "sha256-ZBq9xjYoa5XUB9ROzYroDu7+puzr02iJN3J6ZOAxomA=";
            "aarch64-darwin" = "sha256-XeFcN4Wt/Qdda5h9xANe7vwLUZox7RwZEqNbcRkqv6A=";
          };
          repo = "router-for-me/CLIProxyAPI";
          archivePrefix = "CLIProxyAPI";
          binaryName = "cli-proxy-api";
          license = pkgs: pkgs.lib.licenses.mit;
          description = "AI CLI proxy service providing OpenAI/Gemini/Claude compatible API";
          homepage = "https://github.com/router-for-me/CLIProxyAPI";
        };
        cliproxyapi-plus = {
          version = "6.8.55-0";
          hashes = {
            "x86_64-linux" = "sha256-fWq4r//856qGlsUfww+h1b94l6hcwu+ib509EUZd9pc=";
            "aarch64-linux" = "sha256-BkpQGJwrT5onBUSBzJnWnYnDNRE4cklAS6w6r+TmXKQ=";
            "x86_64-darwin" = "sha256-Xz8/KD76zebX2EvmE9U0ocsKyGh6mpXc4jRoTsHjCcs=";
            "aarch64-darwin" = "sha256-LbUFMhapN/jkvLZ7rKV8Gkq+SpNLeRDsaEnSEtUmlaM=";
          };
          repo = "router-for-me/CLIProxyAPIPlus";
          archivePrefix = "CLIProxyAPIPlus";
          binaryName = "cli-proxy-api-plus";
          license = pkgs: pkgs.lib.licenses.mit;
          description = "AI CLI proxy service (Plus edition) with enhanced features";
          homepage = "https://github.com/router-for-me/CLIProxyAPIPlus";
        };
        cliproxyapi-business = {
          version = "2026.11.0";
          hashes = {
            "x86_64-linux" = "sha256-hzGxDjpIKGyjPv7Qc31in2I7G4oyj7uF7bZ9kw/NDvw=";
            "aarch64-linux" = "sha256-MgA+I2tJqdbduN0H89fQesBjDaKoFvWbUoqZJoLK7mY=";
            "x86_64-darwin" = "sha256-KUPW51riU2q5FwhvuDzER3bz6GXt3dgMxZpAJSjQcEU=";
            "aarch64-darwin" = "sha256-7eqs57m5mwGRzeaD2ExbZ+OeQzZaeZ57+l1qvf2/Avk=";
          };
          repo = "router-for-me/CLIProxyAPIBusiness";
          archivePrefix = "cpab";
          binaryName = "cpab";
          license = pkgs: pkgs.lib.licenses.sspl;
          description = "AI CLI proxy service (Business edition) for enterprise use";
          homepage = "https://github.com/router-for-me/CLIProxyAPIBusiness";
        };
      };

      # Package builder for each system and edition
      mkPackage = pkgs: system: editionName: edition:
        let
          asset = systemToAsset system;
        in
        pkgs.stdenv.mkDerivation {
          pname = editionName;
          version = edition.version;

          src = pkgs.fetchurl {
            url = "https://github.com/${edition.repo}/releases/download/v${edition.version}/${edition.archivePrefix}_${edition.version}_${asset}.tar.gz";
            hash = edition.hashes.${system};
          };

          sourceRoot = ".";

          nativeBuildInputs = [ pkgs.autoPatchelfHook ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp ${edition.binaryName} $out/bin/cliproxyapi

            # Install the example config for reference
            mkdir -p $out/share/cliproxyapi
            if [ -f config.example.yaml ]; then
              cp config.example.yaml $out/share/cliproxyapi/
            fi

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = edition.description;
            homepage = edition.homepage;
            license = edition.license pkgs;
            platforms = supportedSystems;
            mainProgram = "cliproxyapi";
          };
        };

    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      in
      {
        packages = builtins.mapAttrs (name: edition: mkPackage pkgs system name edition) editions
          // { default = self.packages.${system}.cliproxyapi; };

        apps = builtins.mapAttrs (name: pkg: flake-utils.lib.mkApp { drv = pkg; name = "cliproxyapi"; }) self.packages.${system}
          // { default = self.apps.${system}.cliproxyapi; };
      }
    ) // {
      # NixOS module
      nixosModules = {
        cliproxyapi = import ./modules/nixos.nix self;
        default = self.nixosModules.cliproxyapi;
      };

      # nix-darwin module
      darwinModules = {
        cliproxyapi = import ./modules/darwin.nix self;
        default = self.darwinModules.cliproxyapi;
      };

      # Overlay for use with nixpkgs
      overlays.default = final: prev:
        builtins.mapAttrs (name: edition:
          self.packages.${prev.system}.${name}
        ) editions;
    };
}
