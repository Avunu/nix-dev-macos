{
  description = "macOS development system (nix-darwin)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nix on this Mac is installed by the Determinate installer, which manages
    # nix itself; nix-darwin must leave it alone (nix.enable = false) and this
    # module is how nix settings reach /etc/nix/nix.custom.conf instead.
    determinate = {
      url = "github:DeterminateSystems/determinate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pre-commit hooks, run by `nix flake check` and installed by the devShell.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      determinate,
      git-hooks,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Who the machine is configured for. `sudo darwin-rebuild` strips the
      # environment but sets SUDO_USER, and the daily launchd job gets it from
      # `devHost.username` as baked at the previous switch — so, as in
      # nixos-wsl, the rebuild is --impure.
      invokingUser =
        let
          sudoUser = builtins.getEnv "SUDO_USER";
          user = builtins.getEnv "USER";
        in
        if sudoUser != "" then
          sudoUser
        else if user != "" && user != "root" then
          user
        else
          throw "Cannot tell which user to configure: run `sudo darwin-rebuild ... --impure` from your own account";

      detectedSystem =
        let
          detected = builtins.currentSystem;
        in
        if builtins.elem detected systems then
          detected
        else
          throw "Unsupported system ${detected}: expected one of ${builtins.concatStringsSep ", " systems}";

      # A host flake (this one, or a downstream one such as macos-host-kevin)
      # calls this with its own `self`, the flake reference it upgrades from,
      # and extra modules. Everything in modules/dev.nix is inherited.
      mkHost =
        {
          self,
          upgradeFlake,
          modules ? [ ],
        }:
        {
          # The one configuration every Mac runs, straight from the host's
          # repository:
          #   sudo darwin-rebuild switch --flake <upgradeFlake> --refresh --impure
          # Nix cannot enumerate hostnames, but --impure is already required
          # for the user, so the architecture is detected the same way instead
          # of naming one configuration per machine or per arch. Inputs are
          # pinned by the host's flake.lock, which Dependabot moves; the daily
          # launchd job picks up each merge to `main`.
          darwinConfigurations.default = nix-darwin.lib.darwinSystem {
            system = detectedSystem;
            specialArgs = { inherit inputs; };
            modules = [
              (import ./modules/dev.nix { inherit inputs; })
              {
                # What `system-upgrade` compares against the repository's HEAD.
                system.configurationRevision = self.rev or self.dirtyRev or null;
                devHost = {
                  username = invokingUser;
                  inherit upgradeFlake;
                };
              }
            ]
            ++ modules;
          };

          packages = forAllSystems (system: {
            system-upgrade = import ./pkgs/system-upgrade.nix {
              pkgs = nixpkgs.legacyPackages.${system};
              darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;
              flake = upgradeFlake;
              extraFlags = "--impure";
            };
          });
        };

      host = mkHost {
        inherit self;
        upgradeFlake = "github:Avunu/nix-dev-macos#default";
      };
    in
    {
      darwinModules.dev = import ./modules/dev.nix { inherit inputs; };
      darwinModules.default = self.darwinModules.dev;

      lib = { inherit mkHost invokingUser; };

      inherit (host) darwinConfigurations packages;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Forces a full evaluation of the configuration without building it.
          # The user comes from the environment, so this check needs --impure
          # (the CI workflow passes it).
          eval = pkgs.runCommand "darwin-eval-check" { } ''
            echo "${builtins.unsafeDiscardStringContext self.darwinConfigurations.default.system.drvPath}" > "$out"
          '';

          pre-commit = git-hooks.lib.${system}.run {
            src = ./.;
            hooks.nixfmt = {
              enable = true;
              package = pkgs.nixfmt;
            };
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt
              pkgs.prek
            ];
            inherit (self.checks.${system}.pre-commit) shellHook;
          };
        }
      );
    };
}
