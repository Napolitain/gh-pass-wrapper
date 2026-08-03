{
  lib,
  writeShellApplication,
  gawk,
  gh,
  pass,
  secretPath ? "github/token",
}:

let
  wrapper = writeShellApplication {
    name = "gh";

    text = ''
      # Never let caller-enabled tracing print the retrieved credential.
      set +x

      # Do not expose caller-provided GitHub credentials to pass or GnuPG.
      # Clearing gh_token also removes any export attribute before it holds the
      # secret.
      unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN gh_token

      if [[ "$#" -ge 2 && "$1" == "auth" ]]; then
        case "$2" in
          login|refresh|logout|setup-git|switch)
            printf 'gh auth %s is disabled: authentication is managed through GNU pass entry %s.\n' \
              "$2" ${lib.escapeShellArg secretPath} >&2
            exit 64
            ;;
        esac
      fi

      if ! gh_token="$(
        "${pass}/bin/pass" show ${lib.escapeShellArg secretPath} |
          "${gawk}/bin/awk" '
            NR > 1 { invalid = 1 }
            NR == 1 {
              if ($0 == "") invalid = 1
              token = $0
            }
            END {
              if (NR != 1 || invalid) exit 65
              printf "%s", token
            }
          '
      )"; then
        unset gh_token
        printf 'Unable to load a GitHub token from GNU pass entry %s.\n' \
          ${lib.escapeShellArg secretPath} >&2
        printf 'Store exactly one nonempty token line with: pass insert %s\n' \
          ${lib.escapeShellArg secretPath} >&2
        exit 78
      fi

      export GH_TOKEN="$gh_token"
      unset gh_token
      exec "${gh}/bin/gh" "$@"
    '';
  };
in
wrapper.overrideAttrs (old: {
  name = "gh-pass-wrapper-0.1.0";
  pname = "gh-pass-wrapper";
  version = "0.1.0";

  meta = (old.meta or { }) // {
    description = "Fail-closed GitHub CLI wrapper backed by GNU pass";
    homepage = "https://github.com/Napolitain/gh-pass-wrapper";
    license = lib.licenses.mit;
    mainProgram = "gh";
    platforms = lib.platforms.linux;
  };
})
