# ssh-sync-ak

POSIX `sh` only. Load the `shell-scripting` skill.

## Pre-commit

```
shfmt -i 3 -sr -ci -s -w ssh-sync-ak.sh test.sh test-live.sh
shellcheck -s sh ssh-sync-ak.sh test.sh test-live.sh
dash test.sh
```

`test-live.sh` hits the network. Do not run it as a gate.

## Do not commit

Private keys, `.env`, `LOCAL.md`, or anything under `tmp/`. GitHub `*.keys` URLs are public; still keep live fetches in `tmp/`.
