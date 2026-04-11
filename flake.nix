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
          version = "6.9.22";
          hashes = {
            "x86_64-linux" = "sha256-6ssl9sKU/74nkWwuvVLSLXdvu5/kTshR5tZsz+9PEkk=";
            "aarch64-linux" = "sha256-ROGDFE4GsuDNTqoW5tq8yzXvif3Xnhk8RD3X1gZzXJg=";
            "x86_64-darwin" = "sha256-xqyR+GANFCVAbbtgdmPYzNwYF1DmON66jVHrQT7LUjI=";
            "aarch64-darwin" = "sha256-pv6Attpj3BFdNMlVu5QAJsEXB4vL5ScPoKYVjMPyPM0=";
          };
          repo = "router-for-me/CLIProxyAPI";
          archivePrefix = "CLIProxyAPI";
          binaryName = "cli-proxy-api";
          license = pkgs: pkgs.lib.licenses.mit;
          description = "AI CLI proxy service providing OpenAI/Gemini/Claude compatible API";
          homepage = "https://github.com/router-for-me/CLIProxyAPI";
        };
        cliproxyapi-plus = {
          version = "6.9.19-0";
          hashes = {
            "x86_64-linux" = "sha256-SMva7mdhLtdh6oZ3d7DfZoRcQY2Gl/2ElKwQ78FxGo0=";
            "aarch64-linux" = "sha256-868+Bb6MRhjHXdEK5ZdrCirYSoQzXyBn8UsjqjXElLA=";
            "x86_64-darwin" = "sha256-UdqLViZSyeAtlSeL8TSVpIqffRGY2mM9tSbqbSRIVlo=";
            "aarch64-darwin" = "sha256-QgQD1shc7EYMbzrWmOJIemEbI8hlMezExgNtP/zhZFA=";
          };
          repo = "router-for-me/CLIProxyAPIPlus";
          archivePrefix = "CLIProxyAPIPlus";
          binaryName = "cli-proxy-api-plus";
          license = pkgs: pkgs.lib.licenses.mit;
          description = "AI CLI proxy service (Plus edition) with enhanced features";
          homepage = "https://github.com/router-for-me/CLIProxyAPIPlus";
        };
        cliproxyapi-business = {
          version = "2026.13.0";
          hashes = {
            "x86_64-linux" = "sha256-5nf7fH76xKDeHIftekOeXvriy5s6cGfYoiSngQ4ducw=";
            "aarch64-linux" = "sha256-M/Xwm/gpTIB+uW0Yq50WaTa9cwhDNHXMLHUiozaTTdU=";
            "x86_64-darwin" = "sha256-hkNZ7BlukZpTP5j+Wctexa0cbmJV9bRjG7vN7+UmCvg=";
            "aarch64-darwin" = "sha256-Q6rVdkZkaueFNX5/0Pl618lGlUvxiWPlAkqbdntkw6E=";
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
