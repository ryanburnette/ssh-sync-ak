#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL

g_root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
g_script="${g_root}/ssh-sync-ak.sh"
g_work="${TMPDIR:-/tmp}/ssh-sync-ak-test.$$"
mkdir "$g_work"
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

g_updated_re='# updated [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

fn_has_updated() {
   grep -E -x -e "$g_updated_re" "$g_auth" > /dev/null
}

fn_line_after_begin() {
   awk -v n="$1" '
      $0 == "# BEGIN ssh-sync-ak " n { getline; print; exit }
   ' "$g_auth"
}

fn_in_time_window() {
   a_t0=$1
   a_ts=$2
   a_t1=$3
   b_lo=$(printf '%s\n%s\n' "$a_t0" "$a_ts" | sort | sed -n '1p')
   b_hi=$(printf '%s\n%s\n' "$a_ts" "$a_t1" | sort | sed -n '$p')
   test "$b_lo" = "$a_t0" && test "$b_hi" = "$a_t1"
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
if grep -F -x -e "# BEGIN ssh-sync-ak Ryan" "$g_auth" > /dev/null &&
   fn_has_updated &&
   grep -F -x -e "$k1" "$g_auth" > /dev/null &&
   grep -F -x -e "$k2" "$g_auth" > /dev/null &&
   grep -F -x -e "# END ssh-sync-ak Ryan" "$g_auth" > /dev/null; then
   fn_pass 'creates named block'
else
   fn_fail 'creates named block'
fi

# Re-run keeps one copy of each key and an updated timestamp line.
fn_run "$g_keys" Ryan
b_k1_count=$(grep -c -F -x -e "$k1" "$g_auth" || true)
b_k2_count=$(grep -c -F -x -e "$k2" "$g_auth" || true)
b_begin_count=$(grep -c -F -x -e "# BEGIN ssh-sync-ak Ryan" "$g_auth" || true)
if test "$b_k1_count" -eq 1 &&
   test "$b_k2_count" -eq 1 &&
   test "$b_begin_count" -eq 1 &&
   fn_has_updated; then
   fn_pass 're-run keeps keys'
else
   fn_fail 're-run keeps keys'
fi

# Updated line: under BEGIN, UTC now, one per block.
printf '%s\n' "$k1" > "$g_keys"
printf '%s\n' "$k3" > "$g_auth"
b_t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fn_run "$g_keys" Ryan
b_t1=$(date -u +%Y-%m-%dT%H:%M:%SZ)
b_stamp=$(fn_line_after_begin Ryan)
b_ts=${b_stamp#\# updated }
b_updated_count=$(grep -c -E -x -e "$g_updated_re" "$g_auth" || true)
if printf '%s\n' "$b_stamp" | grep -E -x -e "$g_updated_re" > /dev/null &&
   test "$b_updated_count" -eq 1 &&
   fn_in_time_window "$b_t0" "$b_ts" "$b_t1" &&
   grep -F -x -e "$k3" "$g_auth" > /dev/null; then
   fn_pass 'writes updated timestamp'
else
   fn_fail 'writes updated timestamp'
   printf '%s\n' "stamp=$b_stamp t0=$b_t0 t1=$b_t1" >&2
   cat "$g_auth" >&2
fi

# Re-run replaces the timestamp line instead of stacking another.
fn_run "$g_keys" Ryan
b_updated_count=$(grep -c -E -x -e "$g_updated_re" "$g_auth" || true)
b_stamp=$(fn_line_after_begin Ryan)
if test "$b_updated_count" -eq 1 &&
   printf '%s\n' "$b_stamp" | grep -E -x -e "$g_updated_re" > /dev/null; then
   fn_pass 're-run replaces timestamp'
else
   fn_fail 're-run replaces timestamp'
   cat "$g_auth" >&2
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
b_alice=$(fn_line_after_begin Alice)
b_bob=$(fn_line_after_begin Bob)
if grep -F -x -e "# BEGIN ssh-sync-ak Alice" "$g_auth" > /dev/null &&
   grep -F -x -e "# BEGIN ssh-sync-ak Bob" "$g_auth" > /dev/null &&
   printf '%s\n' "$b_alice" | grep -E -x -e "$g_updated_re" > /dev/null &&
   printf '%s\n' "$b_bob" | grep -E -x -e "$g_updated_re" > /dev/null &&
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
      ! grep -F -e 'BEGIN ssh-sync-ak' "$g_auth" > /dev/null; then
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
   printf '%s\n' "$b_out" | grep -E -e "$g_updated_re" > /dev/null &&
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
   ! grep -F -e 'BEGIN ssh-sync-ak' "$b_other" > /dev/null; then
   fn_pass '--file overrides SSH_AK_FILE'
else
   fn_fail '--file overrides SSH_AK_FILE'
fi

if test "$g_failed" -ne 0; then
   exit 1
fi

printf 'all tests passed\n'
