{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.devHost;

  systemUpgrade = import ../pkgs/system-upgrade.nix {
    inherit pkgs;
    inherit (inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}) darwin-rebuild;
    flake = cfg.upgradeFlake;
    extraFlags = "--impure";
  };
in
{
  imports = [ inputs.determinate.darwinModules.default ];

  options.devHost = {
    username = mkOption {
      type = types.str;
      description = "The user this Mac is configured for (primary user, trusted nix user)";
    };
    upgradeFlake = mkOption {
      type = types.str;
      default = "github:Avunu/nix-dev-macos#default";
      description = ''
        The flake `system-upgrade` (and its daily launchd job) rebuilds from.
        The repository's revision is compared with the running system's, so a
        rebuild happens only when a merge (e.g. Dependabot's) landed.
      '';
    };
    autoUpgrade = mkOption {
      type = types.bool;
      default = true;
      description = "Run `system-upgrade` daily from launchd";
    };
    upgradeHour = mkOption {
      type = types.ints.between 0 23;
      default = 4;
      description = "Hour of day for the upgrade job; a run missed while asleep fires on wake";
    };
    stateVersion = mkOption {
      type = types.int;
      default = 6;
      description = "nix-darwin state version";
    };
    ccache = mkOption {
      type = types.bool;
      default = true;
      description = "Install ccache";
    };
    containers = mkOption {
      type = types.bool;
      default = true;
      description = "Install podman and compose tooling";
    };
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages to install";
    };
    brews = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Homebrew formulae (Homebrew itself must already be installed)";
    };
    casks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Homebrew casks (Homebrew itself must already be installed)";
    };
  };

  config = {
    system.stateVersion = cfg.stateVersion;
    system.primaryUser = cfg.username;

    nixpkgs.config.allowUnfree = mkDefault true;

    environment.systemPackages =
      with pkgs;
      flatten [
        (python3.withPackages (
          python-pkgs: with python-pkgs; [
            black
            flake8
            isort
            pandas
            requests
          ]
        ))
        [
          bun
          cmake
          curl
          gh
          git
          gnumake
          nano
          nixfmt
          nodejs_latest
          wget
        ]
        (optionals cfg.ccache [ ccache ])
        (optionals cfg.containers [
          docker-client
          docker-compose
          podman
          podman-compose
        ])
        [ systemUpgrade ]
        cfg.extraPackages
      ];

    programs.zsh.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Nix itself belongs to the Determinate installer; its settings go to
    # /etc/nix/nix.custom.conf through this module.
    nix.enable = false;
    determinateNix.customSettings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      keep-outputs = true;
      keep-derivations = true;
      extra-substituters = [
        "https://nix-community.cachix.org?priority=41"
        "https://numtide.cachix.org?priority=42"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      ];
      trusted-users = [
        "root"
        cfg.username
        "@admin"
      ];
    };

    # Homebrew is only managed when something asks for it, and never
    # uninstalls what the user installed by hand.
    homebrew = mkIf (cfg.brews != [ ] || cfg.casks != [ ]) {
      enable = true;
      inherit (cfg) brews casks;
      onActivation.cleanup = "none";
    };

    # Daily upgrade, the launchd counterpart of nixos-wsl's systemd timer.
    # launchd runs a calendar job missed during sleep once on wake. SUDO_USER
    # is how the flake knows whom to configure (it is evaluated --impure), and
    # root has no other way to supply it here.
    launchd.daemons.system-upgrade = mkIf cfg.autoUpgrade {
      serviceConfig = {
        ProgramArguments = [ (getExe systemUpgrade) ];
        StartCalendarInterval = [
          {
            Hour = cfg.upgradeHour;
            Minute = 0;
          }
        ];
        EnvironmentVariables = {
          HOME = "/var/root";
          SUDO_USER = cfg.username;
        };
        # A full evaluation and rebuild, unattended: be the process that yields.
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 19;
        StandardOutPath = "/var/log/system-upgrade.log";
        StandardErrorPath = "/var/log/system-upgrade.log";
      };
    };
  };
}
