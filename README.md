# nix-dev-macos

A nix-darwin flake for a macOS development machine, the counterpart of
[nixos-wsl](https://github.com/Avunu/nixos-wsl) and
[nixos-dev-host](https://github.com/Avunu/nixos-dev-host).

## What you get

- The same toolchain: Python (black, flake8, isort, pandas, requests), Node, Bun,
  cmake, make, ccache, gh, git, curl, wget, nano, nixfmt, direnv + nix-direnv,
  and podman / docker-compose for containers.
- Nix settings equivalent to the other hosts (flakes, nix-community and numtide
  caches, keep-outputs/derivations). Nix is assumed to come from the
  [Determinate installer](https://docs.determinate.systems/), so nix-darwin does
  not manage the daemon; settings go to `/etc/nix/nix.custom.conf`.
- A daily launchd job (`system-upgrade`, 04:00 by default; a run missed while
  asleep fires on wake) that rebuilds from this repository **only when its
  revision differs from the running system's**.

## Install

1. Install Nix (Determinate installer).
2. First activation (nix-darwin is not installed yet):

   ```bash
   sudo nix run nix-darwin/master#darwin-rebuild -- switch \
     --flake github:Avunu/nix-dev-macos#default --refresh --impure
   ```

   The `default` configuration detects the Mac's architecture (and your user), so the same command works on any Apple Silicon or Intel Mac, whatever its hostname. If activation complains about existing
   `/etc/*` files, move them aside as it instructs (e.g. `sudo mv /etc/zshrc /etc/zshrc.before-nix-darwin`).
3. From then on `darwin-rebuild` and `system-upgrade` are on your PATH.

`--impure` is needed because the user is taken from `SUDO_USER` and the architecture from `builtins.currentSystem`.

## Updates

Dependabot moves the flake inputs in this repository's `flake.lock`. Once a
change lands on `main` the daily job pulls and applies it. Run `system-upgrade`
to pull it in sooner. Logs: `/var/log/system-upgrade.log`.

## Customising

Fork it or set options in `flake.nix` under `devHost`: `extraPackages`, `ccache`, `containers`, `autoUpgrade`, `upgradeHour`, `upgradeFlake`.
Also change `upgradeFlake`'s default in `modules/dev.nix` and the URLs in
`flake.nix` if you fork, so the job pulls from your repository.

## Development

```bash
nix develop                          # nixfmt, prek, pre-commit hooks
nix flake check --impure             # eval of both configurations + hooks
nix build .#system-upgrade
nix fmt
```
