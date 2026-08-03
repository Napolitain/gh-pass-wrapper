{ pkgs }:

let
  fakePass = pkgs.writeShellScriptBin "pass" ''
    set -o nounset

    if [[ -v GH_TOKEN \
      || -v GITHUB_TOKEN \
      || -v GH_ENTERPRISE_TOKEN \
      || -v GITHUB_ENTERPRISE_TOKEN \
      || -v gh_token ]]; then
      echo "pass inherited a GitHub token" >&2
      exit 97
    fi

    expected_path="''${PASS_TEST_EXPECTED_PATH:-github/token}"
    if [[ "$#" -ne 2 || "$1" != "show" || "$2" != "$expected_path" ]]; then
      echo "unexpected pass invocation" >&2
      exit 98
    fi

    case "''${PASS_TEST_SCENARIO:-success}" in
      success)
        printf 'pass-token\n'
        ;;
      failure)
        echo "simulated pass failure" >&2
        exit 42
        ;;
      empty)
        printf '\n'
        ;;
      multiline)
        printf 'first-line\nsecond-line\n'
        ;;
      trailing-empty-line)
        printf 'first-line\n\n'
        ;;
      *)
        echo "unknown pass test scenario" >&2
        exit 99
        ;;
    esac
  '';

  fakeGh = pkgs.writeShellScriptBin "gh" ''
    set -o nounset

    printf 'invoked\n' >> "''${REAL_GH_INVOKED_FILE:?}"

    case "''${1:-}" in
      inspect-env)
        if [[ "''${GH_TOKEN:-}" != "pass-token" ]]; then
          echo "unexpected GH_TOKEN" >&2
          exit 90
        fi
        if [[ -v GITHUB_TOKEN ]]; then
          echo "GITHUB_TOKEN was not cleared" >&2
          exit 91
        fi
        if [[ -v GH_ENTERPRISE_TOKEN || -v GITHUB_ENTERPRISE_TOKEN ]]; then
          echo "enterprise GitHub tokens were not cleared" >&2
          exit 95
        fi
        if [[ -v gh_token ]]; then
          echo "gh_token was inherited" >&2
          exit 94
        fi
        printf 'environment-ok\n'
        ;;
      preserve-arguments)
        if [[ "$#" -ne 5 \
          || "$2" != "space argument" \
          || "$3" != "" \
          || "$4" != "*" \
          || "$5" != "--flag=value" ]]; then
          echo "arguments changed" >&2
          exit 92
        fi
        printf 'arguments-ok\n'
        ;;
      streams)
        IFS= read -r input
        printf 'stdout:%s\n' "$input"
        printf 'stderr:%s\n' "$input" >&2
        exit "''${GH_TEST_EXIT:-0}"
        ;;
      auth)
        printf 'auth:%s\n' "''${2:-}"
        ;;
      *)
        echo "unexpected fake gh invocation" >&2
        exit 93
        ;;
    esac
  '';

  secureGh = pkgs.callPackage ../package.nix {
    gh = fakeGh;
    pass = fakePass;
  };

  customPathGh = pkgs.callPackage ../package.nix {
    gh = fakeGh;
    pass = fakePass;
    secretPath = "custom/github/token";
  };
in
pkgs.runCommand "gh-pass-wrapper-test" { } ''
  set -o errexit
  set -o nounset
  set -o pipefail

  wrapper=${secureGh}/bin/gh
  invoked="$PWD/real-gh-invoked"
  export REAL_GH_INVOKED_FILE="$invoked"

  : > "$invoked"
  output="$(${pkgs.coreutils}/bin/env \
    PASS_TEST_SCENARIO=success \
    GH_TOKEN=caller-gh-token \
    GITHUB_TOKEN=caller-github-token \
    GH_ENTERPRISE_TOKEN=caller-enterprise-token \
    GITHUB_ENTERPRISE_TOKEN=caller-github-enterprise-token \
    gh_token=caller-lowercase-token \
    "$wrapper" inspect-env)"
  [[ "$output" == "environment-ok" ]]
  [[ "$(${pkgs.coreutils}/bin/wc -l < "$invoked")" -eq 1 ]]

  for scenario in failure empty multiline trailing-empty-line; do
    : > "$invoked"
    set +o errexit
    PASS_TEST_SCENARIO="$scenario" "$wrapper" inspect-env \
      > "$PWD/$scenario.stdout" 2> "$PWD/$scenario.stderr"
    status="$?"
    set -o errexit
    if [[ "$status" -eq 0 ]]; then
      echo "wrapper accepted invalid pass scenario: $scenario" >&2
      exit 1
    fi
    [[ "$status" -eq 78 ]]
    [[ ! -s "$invoked" ]]
    ${pkgs.gnugrep}/bin/grep -F \
      "Store exactly one nonempty token line with: pass insert github/token" \
      "$PWD/$scenario.stderr" > /dev/null
    ! ${pkgs.gnugrep}/bin/grep -E \
      'pass-token|first-line|second-line|caller-(gh|github|enterprise)' \
      "$PWD/$scenario.stdout" "$PWD/$scenario.stderr" > /dev/null
  done

  for subcommand in login refresh logout setup-git switch; do
    : > "$invoked"
    set +o errexit
    PASS_TEST_SCENARIO=failure "$wrapper" auth "$subcommand" \
      > "$PWD/auth-$subcommand.stdout" 2> "$PWD/auth-$subcommand.stderr"
    status="$?"
    set -o errexit
    if [[ "$status" -eq 0 ]]; then
      echo "wrapper accepted blocked auth command: $subcommand" >&2
      exit 1
    fi
    [[ "$status" -eq 64 ]]
    [[ ! -s "$invoked" ]]
    ${pkgs.gnugrep}/bin/grep -F \
      "gh auth $subcommand is disabled" \
      "$PWD/auth-$subcommand.stderr" > /dev/null
  done

  for subcommand in status token; do
    : > "$invoked"
    output="$(PASS_TEST_SCENARIO=success "$wrapper" auth "$subcommand")"
    [[ "$output" == "auth:$subcommand" ]]
    [[ "$(${pkgs.coreutils}/bin/wc -l < "$invoked")" -eq 1 ]]
  done

  : > "$invoked"
  output="$(PASS_TEST_SCENARIO=success "$wrapper" \
    preserve-arguments "space argument" "" '*' --flag=value)"
  [[ "$output" == "arguments-ok" ]]

  printf 'input payload\n' > "$PWD/stdin"
  set +o errexit
  PASS_TEST_SCENARIO=success GH_TEST_EXIT=23 "$wrapper" streams \
    < "$PWD/stdin" > "$PWD/stdout" 2> "$PWD/stderr"
  status="$?"
  set -o errexit
  [[ "$status" -eq 23 ]]
  [[ "$(< "$PWD/stdout")" == "stdout:input payload" ]]
  [[ "$(< "$PWD/stderr")" == "stderr:input payload" ]]

  : > "$invoked"
  PASS_TEST_SCENARIO=success ${pkgs.bash}/bin/bash -x "$wrapper" inspect-env \
    > "$PWD/xtrace.stdout" 2> "$PWD/xtrace.stderr"
  ! ${pkgs.gnugrep}/bin/grep -F "pass-token" "$PWD/xtrace.stderr" > /dev/null

  : > "$invoked"
  output="$(PASS_TEST_SCENARIO=success \
    PASS_TEST_EXPECTED_PATH=custom/github/token \
    ${customPathGh}/bin/gh inspect-env)"
  [[ "$output" == "environment-ok" ]]
  [[ "$(${pkgs.coreutils}/bin/wc -l < "$invoked")" -eq 1 ]]

  touch "$out"
''
