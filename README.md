# gh-pass-wrapper

`gh-pass-wrapper` is a fail-closed launcher for the GitHub CLI on Linux. It
retrieves a personal access token (PAT) from GNU `pass`, validates the result,
and executes stock `gh` with the token in `GH_TOKEN` for that process only.

The installed executable is named `gh`, so consumers can expose it as the
normal GitHub CLI command instead of leaving an unprotected stock `gh` earlier
on `PATH`.

## Why a wrapper is needed

GNU `pass` is not a storage backend for `gh auth login`. The wrapper instead
uses a separately provisioned PAT and prevents the persistent GitHub CLI auth
commands that could reintroduce credentials in `~/.config/gh/hosts.yml`.

For an allowed command, the runtime flow is:

```text
gh command
  -> pass show github/token
  -> GPG decryption and pinentry when needed
  -> one-line validation
  -> GH_TOKEN in stock gh's process environment
  -> GitHub API
```

The default password-store entry is `github/token`. It must contain exactly one
nonempty line.

## Behavior

The wrapper:

- clears inherited GitHub and GitHub Enterprise token variables before calling
  `pass`;
- refuses to start stock `gh` if `pass` fails or returns an empty or multiline
  value;
- blocks `gh auth login`, `refresh`, `logout`, `setup-git`, and `switch` before
  secret retrieval;
- preserves arguments, standard streams, terminal behavior, and the stock
  `gh` exit status;
- disables shell tracing before handling a credential;
- calls both `pass` and stock `gh` through absolute Nix-store paths.

Read-only commands such as `gh auth status` retain their upstream behavior.
`gh auth token` and `gh auth status --show-token` can print the PAT and should
not be used for routine validation.

## Nix usage

Run the default package directly:

```sh
nix run github:Napolitain/gh-pass-wrapper -- api user --jq .login
```

Consume it from another flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    gh-pass-wrapper = {
      url = "github:Napolitain/gh-pass-wrapper/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, gh-pass-wrapper, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          environment.systemPackages = [
            gh-pass-wrapper.packages.x86_64-linux.default
          ];
        }
      ];
    };
  };
}
```

The package supports `x86_64-linux` and `aarch64-linux`. Consumers can override
the build-time entry path when necessary:

```nix
gh-pass-wrapper.packages.${system}.default.override {
  secretPath = "work/github/token";
}
```

## Provisioning boundary

This project does not create a PAT, initialize `pass`, manage GPG keys, choose
token permissions, configure Git transport, revoke old credentials, or manage
`gpg-agent` and pinentry. Those are deployment and account-owner
responsibilities.

A typical attended setup uses interactive commands such as:

```sh
pass init FULL_GPG_FINGERPRINT
pass insert github/token
gh api user --jq .login
```

Never place a PAT in a shell argument or repository file.

## Security boundary

The password store is local user state. This repository never runs `pass git
init`, configures a password-store remote, or synchronizes
`~/.password-store`. Do not commit or upload the store, including the encrypted
`github/token.gpg` file. The repository also never contains GPG private keys or
real PAT fixtures.

Encryption at rest cannot protect a token while it is being used. The PAT
exists transiently in the wrapper and stock `gh` process environment and
memory. Trusted `gh` extensions or child processes may inherit it, and the
account itself or `root` may be able to inspect a running process. Do not run
untrusted extensions or commands through the wrapper.

## Development

```sh
nix flake check --print-build-logs
nix build .#packages.x86_64-linux.default
nix run --inputs-from . nixpkgs#statix -- check .
```
