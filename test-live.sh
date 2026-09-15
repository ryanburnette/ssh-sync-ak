#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL

# Exercise ssh-sync-ak.sh against https://github.com/ryanburnette.keys
# using copies of testdata files under tmp/.

g_root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
g_script="${g_root}/ssh-sync-ak.sh"
g_url='https://github.com/ryanburnette.keys'
g_tmp="${g_root}/tmp"

mkdir -p "$g_tmp"
cp "${g_root}/testdata/empty.authorized_keys" "${g_tmp}/ak.empty"
cp "${g_root}/testdata/unmanaged.authorized_keys" "${g_tmp}/ak.unmanaged"

printf '== dry run on empty file ==\n'
sh "$g_script" -n -f "${g_tmp}/ak.empty" "$g_url" Ryan

printf '\n== write empty file ==\n'
sh "$g_script" -f "${g_tmp}/ak.empty" "$g_url" Ryan

printf '\n== dry run on unmanaged file ==\n'
sh "$g_script" -n -f "${g_tmp}/ak.unmanaged" "$g_url" Ryan

printf '\n== write unmanaged file ==\n'
sh "$g_script" -f "${g_tmp}/ak.unmanaged" "$g_url" Ryan

printf '\n== second dry run (should be up to date) ==\n'
sh "$g_script" -n -f "${g_tmp}/ak.unmanaged" "$g_url" Ryan

curl -fsSL "$g_url" > "${g_tmp}/ryanburnette.keys"
b_first=$(sed -n '1p' "${g_tmp}/ryanburnette.keys")
if test -z "$b_first"; then
   printf 'test-live: no keys at %s\n' "$g_url" >&2
   exit 1
fi

{
   printf 'from="10.0.0.1" %s\n' "$b_first"
   cat "${g_root}/testdata/unmanaged.authorized_keys"
} > "${g_tmp}/ak.move"

printf '\n== dry run moving an existing GitHub key ==\n'
sh "$g_script" -n -f "${g_tmp}/ak.move" "$g_url" Ryan

printf '\n== write moving an existing GitHub key ==\n'
sh "$g_script" -f "${g_tmp}/ak.move" "$g_url" Ryan

printf '\n== result %s ==\n' "${g_tmp}/ak.move"
cat "${g_tmp}/ak.move"

if ! grep -F -e 'host-local' "${g_tmp}/ak.move" > /dev/null; then
   printf 'test-live: unmanaged key was lost\n' >&2
   exit 1
fi
if grep -F -e 'from="10.0.0.1"' "${g_tmp}/ak.move" > /dev/null; then
   printf 'test-live: options line was not moved into the block\n' >&2
   exit 1
fi
if ! grep -F -x -e "$b_first" "${g_tmp}/ak.move" > /dev/null; then
   printf 'test-live: GitHub key missing from block\n' >&2
   exit 1
fi

printf '\ntest-live: ok\n'
