# nix-darwin module for CLIProxyAPI
flake:

{ config, lib, pkgs, ... }:

let
  cfg = config.services.cliproxyapi;
in
{
  options.services.cliproxyapi = {
    enable = lib.mkEnableOption "CLIProxyAPI service";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.system}.cliproxyapi;
      defaultText = lib.literalExpression "flake.packages.\${pkgs.system}.cliproxyapi";
      description = "The CLIProxyAPI package to use. Available editions: cliproxyapi (base), cliproxyapi-business.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8317;
      description = "Port for CLIProxyAPI to listen on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/cliproxyapi";
      description = "Directory for CLIProxyAPI data (config.yaml, auth tokens).";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a config.yaml file to use. If null, an example config will be
        copied to the data directory on first run for you to customize.

        Note: CLIProxyAPI configuration is complex and varies by use case.
        It's recommended to either:
        - Use the Web UI or Desktop GUI to configure
        - Manually edit the config.yaml file
        - Use remote storage (Git, PostgreSQL, S3) for config management
      '';
    };

    # Storage configuration options
    storage = {
      type = lib.mkOption {
        type = lib.types.enum [ "local" "git" "postgres" "s3" ];
        default = "local";
        description = ''
          Storage backend for configuration and authentication data.
          - local: Store locally in dataDir (default)
          - git: Sync with a Git repository
          - postgres: Store in PostgreSQL database
          - s3: Store in S3-compatible object storage
        '';
      };

      # Git storage options
      git = {
        url = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "HTTPS URL of the Git repository for storage.";
        };

        username = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Username for Git authentication.";
        };

        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File containing the Git personal access token.";
        };
      };

      # PostgreSQL storage options
      postgres = {
        dsnFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            File containing the PostgreSQL connection string.
            Format: postgresql://user:pass@host:5432/db
          '';
        };

        schema = lib.mkOption {
          type = lib.types.str;
          default = "public";
          description = "PostgreSQL schema to use.";
        };
      };

      # S3 storage options
      s3 = {
        endpoint = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "S3-compatible endpoint URL.";
        };

        bucket = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "S3 bucket name.";
        };

        accessKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File containing the S3 access key.";
        };

        secretKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File containing the S3 secret key.";
        };
      };
    };

    # Management UI
    managementPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File containing the password for the management web UI.
        Required when using remote storage backends.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables to pass to CLIProxyAPI.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.storage.type != "git" || cfg.storage.git.url != null;
        message = "services.cliproxyapi.storage.git.url must be set when using git storage.";
      }
      {
        assertion = cfg.storage.type != "postgres" || cfg.storage.postgres.dsnFile != null;
        message = "services.cliproxyapi.storage.postgres.dsnFile must be set when using postgres storage.";
      }
      {
        assertion = cfg.storage.type != "s3" || (cfg.storage.s3.endpoint != null && cfg.storage.s3.bucket != null);
        message = "services.cliproxyapi.storage.s3.endpoint and bucket must be set when using s3 storage.";
      }
      {
        assertion = cfg.storage.type == "local" || cfg.managementPasswordFile != null;
        message = "services.cliproxyapi.managementPasswordFile is required when using remote storage.";
      }
    ];

    # Create the data directory
    system.activationScripts.cliproxyapi-datadir = ''
      mkdir -p ${cfg.dataDir}
      chown _cliproxyapi:staff ${cfg.dataDir} 2>/dev/null || true
    '';

    # Create the user (macOS way)
    users.knownUsers = [ "_cliproxyapi" ];
    users.users._cliproxyapi = {
      uid = 850;
      gid = 20; # staff group
      home = cfg.dataDir;
      shell = "/usr/bin/false";
      description = "CLIProxyAPI service user";
    };

    launchd.daemons.cliproxyapi = {
      serviceConfig = {
        Label = "org.nixos.cliproxyapi";
        ProgramArguments = let
          # Build the wrapper script
          wrapperScript = pkgs.writeShellScript "cliproxyapi-wrapper" ''
            # Set working directory
            cd ${cfg.dataDir}

            # Copy example config if no config exists
            if [ ! -f ${cfg.dataDir}/config.yaml ] && [ -z "${toString cfg.configFile}" ]; then
              if [ -f ${cfg.package}/share/cliproxyapi/config.example.yaml ]; then
                cp ${cfg.package}/share/cliproxyapi/config.example.yaml ${cfg.dataDir}/config.yaml
                chmod 600 ${cfg.dataDir}/config.yaml
              fi
            fi

            # Symlink provided config file if specified
            ${lib.optionalString (cfg.configFile != null) ''
              ln -sf ${cfg.configFile} ${cfg.dataDir}/config.yaml
            ''}

            # Load secrets from files
            ${lib.optionalString (cfg.managementPasswordFile != null) ''
              export MANAGEMENT_PASSWORD="$(cat ${cfg.managementPasswordFile})"
            ''}
            ${lib.optionalString (cfg.storage.type == "git" && cfg.storage.git.tokenFile != null) ''
              export GITSTORE_GIT_TOKEN="$(cat ${cfg.storage.git.tokenFile})"
            ''}
            ${lib.optionalString (cfg.storage.type == "postgres" && cfg.storage.postgres.dsnFile != null) ''
              export PGSTORE_DSN="$(cat ${cfg.storage.postgres.dsnFile})"
            ''}
            ${lib.optionalString (cfg.storage.type == "s3" && cfg.storage.s3.accessKeyFile != null) ''
              export OBJECTSTORE_ACCESS_KEY="$(cat ${cfg.storage.s3.accessKeyFile})"
            ''}
            ${lib.optionalString (cfg.storage.type == "s3" && cfg.storage.s3.secretKeyFile != null) ''
              export OBJECTSTORE_SECRET_KEY="$(cat ${cfg.storage.s3.secretKeyFile})"
            ''}

            # Execute the binary
            exec ${cfg.package}/bin/cliproxyapi
          '';
        in [ "${wrapperScript}" ];

        UserName = "_cliproxyapi";
        GroupName = "staff";
        WorkingDirectory = cfg.dataDir;
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/cliproxyapi.log";
        StandardErrorPath = "/var/log/cliproxyapi.error.log";

        EnvironmentVariables = let
          storageEnv = {
            "local" = { };
            "git" = {
              GITSTORE_GIT_URL = cfg.storage.git.url;
              GITSTORE_LOCAL_PATH = cfg.dataDir;
            } // lib.optionalAttrs (cfg.storage.git.username != null) {
              GITSTORE_GIT_USERNAME = cfg.storage.git.username;
            };
            "postgres" = {
              PGSTORE_LOCAL_PATH = cfg.dataDir;
              PGSTORE_SCHEMA = cfg.storage.postgres.schema;
            };
            "s3" = {
              OBJECTSTORE_ENDPOINT = cfg.storage.s3.endpoint;
              OBJECTSTORE_BUCKET = cfg.storage.s3.bucket;
              OBJECTSTORE_LOCAL_PATH = cfg.dataDir;
            };
          }.${cfg.storage.type};
        in
          storageEnv // cfg.extraEnvironment;
      };
    };
  };
}
