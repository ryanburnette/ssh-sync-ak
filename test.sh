#!/bin/sh
set -eu

g_root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
g_script="${g_root}/ssh-ak-config.sh"
g_work=$(mktemp -d)
trap 'rm -rf "$g_work"' EXIT

g_failed=0

fn_fail() {
   printf 'FAIL: %s\n' "$1" >&2
   g_failed=1
}

fn_pass() {
   printf 'ok: %s\n' "$1"
}

fn_run() {
   sh "$g_script" -f "$g_auth" "$@"
}

g_auth="${g_work}/authorized_keys"
g_keys="${g_work}/keys"

k1='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKey11111111111111111111111111111111111 one'
k2='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKey22222222222222222222222222222222222 two'
k3='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCfakeotherkey3333333333333333333333 other'
k1_opt='from="10.0.0.1" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKey11111111111111111111111111111111111 oldcomment'

# Fresh file: creates the named block.
printf '%s\n' "$k1" "$k2" > "$g_keys"
fn_run "$g_keys" Ryan
if grep -F -x -e "# BEGIN ssh-ak-config Ryan" "$g_auth" > /dev/null &&
   grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   grep -F -x -e "$k2" "$g_auth" > /dev/null &&
   grep -F -x -e "# END ssh-ak-config Ryan" "$g_auth" > /dev/null; then
   fn_pass 'creates named block'
else
   fn_fail 'creates named block'
fi

# Idempotent.
b_before=$(cat "$g_auth")
fn_run "$g_keys" Ryan
b_after=$(cat "$g_auth")
if test "$b_before" = "$b_after"; then
   fn_pass 'idempotent'
else
   fn_fail 'idempotent'
fi

# Preserve unmanaged keys and rotate the block.
printf '%s\n' "$k3" > "$g_auth"
printf '%s\n' "# leftover comment" >> "$g_auth"
printf '%s\n' "$k1" >> "$g_auth"
printf '%s\n' "$k1" "$k2" > "$g_keys"
fn_run "$g_keys" Ryan
if grep -F -x -e "$k3" "$g_auth" > /dev/null &&
   grep -F -x -e "# leftover comment" "$g_auth" > /dev/null &&
   grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   grep -F -x -e "$k2" "$g_auth" > /dev/null; then
   fn_pass 'preserves unmanaged lines'
else
   fn_fail 'preserves unmanaged lines'
fi

# Move a matching key (with options) into the block; only one copy remains.
printf '%s\n' "$k1_opt" > "$g_auth"
printf '%s\n' "$k3" >> "$g_auth"
printf '%s\n' "$k1" > "$g_keys"
fn_run "$g_keys" Ryan
b_count=$(grep -c -e 'AAAAC3NzaC1lZDI1NTE5AAAAIFakeKey11111111111111111111111111111111111' "$g_auth" || true)
if test "$b_count" -eq 1 &&
   grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   ! grep -F -x -e "$k1_opt" "$g_auth" > /dev/null &&
   grep -F -x -e "$k3" "$g_auth" > /dev/null; then
   fn_pass 'moves existing key into the block'
else
   fn_fail 'moves existing key into the block'
   printf '%s\n' "----" >&2
   cat "$g_auth" >&2
   printf '%s\n' "----" >&2
fi

# Two names, two blocks.
printf '%s\n' "$k1" > "$g_keys"
fn_run "$g_keys" Alice
printf '%s\n' "$k2" > "$g_keys"
fn_run "$g_keys" Bob
if grep -F -x -e "# BEGIN ssh-ak-config Alice" "$g_auth" > /dev/null &&
   grep -F -x -e "# BEGIN ssh-ak-config Bob" "$g_auth" > /dev/null &&
   grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   grep -F -x -e "$k2" "$g_auth" > /dev/null; then
   fn_pass 'two named blocks'
else
   fn_fail 'two named blocks'
fi

# Empty keys file fails and does not wipe.
printf '%s\n' "$k3" > "$g_auth"
printf '\n' > "$g_keys"
if fn_run "$g_keys" Ryan 2> /dev/null; then
   fn_fail 'empty keys should fail'
else
   if grep -F -x -e "$k3" "$g_auth" > /dev/null &&
      ! grep -F -e 'BEGIN ssh-ak-config' "$g_auth" > /dev/null; then
      fn_pass 'empty keys aborts'
   else
      fn_fail 'empty keys aborts (file changed)'
   fi
fi

# Invalid name.
if fn_run "$g_keys" 'Ryan Burnette' 2> /dev/null; then
   fn_fail 'invalid name should fail'
else
   fn_pass 'rejects invalid name'
fi

# Missing args.
if sh "$g_script" 2> /dev/null; then
   fn_fail 'missing args should fail'
else
   fn_pass 'rejects missing args'
fi

# Dry run does not write.
printf '%s\n' "$k3" > "$g_auth"
printf '%s\n' "$k1" > "$g_keys"
b_before=$(cat "$g_auth")
b_out=$(fn_run -n "$g_keys" Ryan 2>&1) || true
b_after=$(cat "$g_auth")
if test "$b_before" = "$b_after" &&
   printf '%s\n' "$b_out" | grep -F -e 'dry run' > /dev/null &&
   printf '%s\n' "$b_out" | grep -F -e "$k1" > /dev/null; then
   fn_pass 'dry run does not write'
else
   fn_fail 'dry run does not write'
   printf '%s\n' "$b_out" >&2
fi

# --file= form writes the given path, not SSH_AK_FILE.
b_other="${g_work}/other_keys"
printf '%s\n' "$k3" > "$b_other"
printf '%s\n' "$k1" > "$g_keys"
SSH_AK_FILE="$b_other" sh "$g_script" --file="$g_auth" "$g_keys" Ryan
if grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   grep -F -x -e "$k3" "$b_other" > /dev/null &&
   ! grep -F -e 'BEGIN ssh-ak-config' "$b_other" > /dev/null; then
   fn_pass '--file overrides SSH_AK_FILE'
else
   fn_fail '--file overrides SSH_AK_FILE'
fi

if test "$g_failed" -ne 0; then
   exit 1
fi

printf 'all tests passed\n'
