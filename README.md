# ssh-sync-ak

Sync public keys from a URL into a named block in `authorized_keys`.

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburnette/ssh-sync-ak/main/ssh-sync-ak.sh | sh -s -- https://ryanburnette.com/keys ryanburnette
```

## What it does

1. Fetches keys from the URL (GitHub's `https://github.com/<user>.keys` works).
2. Writes them into a managed block named by the last argument (default `default`). The block includes a UTC `# updated` line for the last write.
3. If any of those keys already appear elsewhere in `authorized_keys`, moves them into the block (the old line is removed, including options).
4. Leaves every other line alone.

Re-running with the same name replaces that block so key rotation works. Other blocks and unmanaged keys stay put.

```
# BEGIN ssh-sync-ak ryanburnette
# updated 2026-04-08T14:30:00Z
ssh-ed25519 AAAA...
# END ssh-sync-ak ryanburnette
```

If the URL has no valid keys, the script exits without changing the file.

## Usage

```
ssh-sync-ak.sh [-n] [-f file] <keys-url> [name]
```

| Option | Meaning |
| --- | --- |
| `-f`, `--file PATH` | `authorized_keys` file. Default `~/.ssh/authorized_keys`. `SSH_AK_FILE` is used if `-f` is omitted. |
| `-n`, `--dry-run` | Print the change. Do not write. |

`keys-url` may be `http://`, `https://`, or a local file. Name may only contain `A-Za-z0-9._-`.

Dry run against a test file:

```
sh ssh-sync-ak.sh -n -f testdata/unmanaged.authorized_keys https://github.com/ryanburnette.keys Ryan
```

Two people, two blocks:

```
... | sh -s -- https://github.com/layne.keys Layne
... | sh -s -- https://github.com/mike.keys Mike
```

## License

MIT. See [LICENSE](LICENSE).
