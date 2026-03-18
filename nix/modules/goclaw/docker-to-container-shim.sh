#!/usr/bin/env bash
# docker → Apple Container CLI shim for goclaw sandbox.
#
# Translates the specific Docker commands goclaw's sandbox issues into Apple
# Container equivalents. Apple Containers run each container in its own
# lightweight VM, so Docker-specific security flags (--cap-drop, --read-only,
# --security-opt, --pids-limit) are unnecessary and silently dropped.
#
# Supported commands:
#   docker info --format ...           → container system version
#   docker run -d [flags] IMAGE CMD    → container run -d [mapped-flags] IMAGE CMD
#   docker exec [-i] [-e K=V] ID CMD  → container exec [-i] ID env K=V CMD
#   docker rm -f ID                    → container delete -f ID
#
# Unsupported commands produce an error message and exit 1.

set -euo pipefail

CONTAINER_CLI="/usr/local/bin/container"

case "${1:-}" in
  info)
    # goclaw calls: docker info --format '{{.ServerVersion}}'
    # Just return a version string if the container system is running.
    if "$CONTAINER_CLI" system version >/dev/null 2>&1; then
      echo "apple-container"
      exit 0
    else
      echo "Apple Container system not running" >&2
      exit 1
    fi
    ;;

  run)
    shift # consume "run"
    ARGS=()
    ENV_ARGS=()
    SKIP_NEXT=false

    while [[ $# -gt 0 ]]; do
      if $SKIP_NEXT; then
        SKIP_NEXT=false
        shift
        continue
      fi

      case "$1" in
        -d|--detach)
          ARGS+=("-d")
          ;;
        --name)
          ARGS+=("--name" "$2")
          shift
          ;;
        --memory)
          ARGS+=("--memory" "$2")
          shift
          ;;
        --cpus)
          ARGS+=("--cpus" "$2")
          shift
          ;;
        -v|--volume)
          ARGS+=("--volume" "$2")
          shift
          ;;
        -w|--workdir)
          ARGS+=("--workdir" "$2")
          shift
          ;;
        -e)
          ENV_ARGS+=("-e" "$2")
          shift
          ;;
        --tmpfs)
          ARGS+=("--tmpfs" "${2%%:*}") # strip size options
          shift
          ;;
        --init)
          ARGS+=("--init")
          ;;
        --rm)
          ARGS+=("--rm")
          ;;
        -i|--interactive)
          ARGS+=("-i")
          ;;
        -t|--tty)
          ARGS+=("-t")
          ;;
        -u|--user)
          ARGS+=("--user" "$2")
          shift
          ;;
        # Docker-only flags — silently drop (Apple VM isolation is stronger)
        --read-only|--security-opt|--cap-drop|--network|--pids-limit|--label)
          # These all take a value argument, skip it
          shift
          ;;
        --)
          shift
          break
          ;;
        -*)
          # Unknown flag — skip with its value
          shift
          ;;
        *)
          # First non-flag arg is the image, rest is the command
          break
          ;;
      esac
      shift
    done

    exec "$CONTAINER_CLI" run "${ARGS[@]}" "${ENV_ARGS[@]}" "$@"
    ;;

  exec)
    shift # consume "exec"
    EXEC_ARGS=()
    ENV_PAIRS=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -i|--interactive)
          EXEC_ARGS+=("-i")
          ;;
        -t|--tty)
          EXEC_ARGS+=("-t")
          ;;
        -w|--workdir)
          EXEC_ARGS+=("--workdir" "$2")
          shift
          ;;
        -u|--user)
          EXEC_ARGS+=("--user" "$2")
          shift
          ;;
        -e)
          # Apple Container exec doesn't support -e; inject via env command
          ENV_PAIRS+=("$2")
          shift
          ;;
        -*)
          # Unknown exec flag — skip
          ;;
        *)
          # First non-flag arg is the container ID
          CONTAINER_ID="$1"
          shift
          break
          ;;
      esac
      shift
    done

    if [[ ${#ENV_PAIRS[@]} -gt 0 ]]; then
      # Prepend env K=V to the command
      exec "$CONTAINER_CLI" exec "${EXEC_ARGS[@]}" "$CONTAINER_ID" env "${ENV_PAIRS[@]}" "$@"
    else
      exec "$CONTAINER_CLI" exec "${EXEC_ARGS[@]}" "$CONTAINER_ID" "$@"
    fi
    ;;

  rm)
    shift # consume "rm"
    # docker rm -f ID → container delete -f ID
    exec "$CONTAINER_CLI" delete "$@"
    ;;

  *)
    echo "docker-shim: unsupported command '$1'" >&2
    exit 1
    ;;
esac
