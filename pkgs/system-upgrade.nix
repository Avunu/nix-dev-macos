# The `system-upgrade` command: rebuild from devHost.upgradeFlake, run by hand
# or by the daily launchd job in modules/dev.nix.
#
# Adapted from nixos-wsl (pkgs/system-upgrade.nix) for nix-darwin. Same guard:
# the repository's flake.lock is authoritative (Dependabot moves it), so
# "something changed" means the repository's revision differs from the one the
# running system was built from.
{
  pkgs,
  darwin-rebuild,
  # A flake reference with an attribute, e.g. github:Avunu/nix-dev-macos#aarch64
  flake,
  # Extra flags for darwin-rebuild, e.g. "--impure". Shell words, unquoted.
  extraFlags ? "",
}:
let
  ref = pkgs.lib.escapeShellArg flake;
in
pkgs.writeShellApplication {
  name = "system-upgrade";
  runtimeInputs = with pkgs; [
    coreutils
    git
    jq
    nix
    darwin-rebuild
  ];
  text = ''
    if [ "$(id -u)" -ne 0 ]; then
      exec sudo --preserve-env=SUDO_USER "$0" "$@"
    fi

    REF=${ref}
    LATEST=$(nix flake metadata --refresh --json "''${REF%%#*}" | jq -r '.revision // .locked.rev // empty')
    CURRENT=$(jq -r '.configurationRevision // empty' /run/current-system/darwin-version.json 2>/dev/null || true)

    # An unknown current revision (a dirty or hand-built deploy) always rebuilds.
    if [ -n "$LATEST" ] && [ "$LATEST" = "$CURRENT" ]; then
      echo "Already at $LATEST, skipping rebuild" >&2
      exit 0
    fi

    darwin-rebuild switch --refresh --flake "$REF" ${extraFlags}
    echo "Upgrade applied." >&2
  '';
}
