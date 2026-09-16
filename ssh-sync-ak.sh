#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL

# Sync public keys from a URL (or file) into a named block in authorized_keys.
# Matching keys already in the file are moved into that block.

g_begin=
g_end=
g_updated=
g_key_body=
g_key_ids=
g_auth_file=
g_name=
g_keys_src=
g_tmp_auth=
g_tmp_keys=
g_dry_run=0

fn_usage() {
   printf 'usage: ssh-sync-ak.sh [-n] [-f file] <keys-url> [name]\n' >&2
   printf '\n' >&2
   printf 'Sync public keys into a named block in authorized_keys.\n' >&2
   printf '\n' >&2
   printf '  -f, --file PATH   authorized_keys file (default ~/.ssh/authorized_keys)\n' >&2
   printf '  -n, --dry-run     print the change and do not write\n' >&2
   printf '\n' >&2
   printf 'Example:\n' >&2
   printf '  curl -fsSL https://raw.githubusercontent.com/ryanburnette/ssh-sync-ak/main/ssh-sync-ak.sh | sh -s -- https://github.com/user.keys Name\n' >&2
   printf '\n' >&2
   printf 'Arguments after sh -s -- are required so the script sees them.\n' >&2
   printf 'Default name is "default". SSH_AK_FILE is used if -f is omitted.\n' >&2
}

fn_http_get() {
   a_url=$1
   if command -v curl > /dev/null 2>&1; then
      curl -fsSL "$a_url"
   elif command -v wget > /dev/null 2>&1; then
      wget -q -O - "$a_url"
   else
      printf 'ssh-sync-ak: need curl or wget to fetch %s\n' "$a_url" >&2
      exit 1
   fi
}

fn_fetch_keys() {
   a_src=$1
   case $a_src in
      http://* | https://*)
         fn_http_get "$a_src"
         ;;
      *)
         if test -f "$a_src"; then
            cat "$a_src"
         else
            fn_http_get "$a_src"
         fi
         ;;
   esac
}

# Print "type blob" for an authorized_keys line, or nothing.
fn_key_id() {
   printf '%s\n' "$1" | tr -d '\r' | awk '{
      for (i = 1; i <= NF; i++) {
         if ($i ~ /^(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-|webauthn-)/) {
            if ((i + 1) <= NF) {
               print $i, $(i + 1)
            }
            exit
         }
      }
   }'
}

fn_ids_contain() {
   a_id=$1
   test -n "$a_id" || return 1
   printf '%s\n' "$g_key_ids" | grep -F -x -e "$a_id" > /dev/null
}

fn_line_is_owned() {
   b_id=$(fn_key_id "$1")
   fn_ids_contain "$b_id"
}

fn_print_block() {
   printf '%s\n' "$g_begin"
   printf '%s\n' "$g_updated"
   printf '%s\n' "$g_key_body"
   printf '%s\n' "$g_end"
}

fn_collect_keys() {
   g_key_body=
   g_key_ids=
   while IFS= read -r b_line || test -n "$b_line"; do
      b_line=$(printf '%s' "$b_line" | tr -d '\r')
      case $b_line in
         '' | \#*)
            continue
            ;;
      esac
      b_id=$(fn_key_id "$b_line")
      if test -z "$b_id"; then
         printf 'ssh-sync-ak: skipping invalid line\n' >&2
         continue
      fi
      if fn_ids_contain "$b_id"; then
         continue
      fi
      if test -z "$g_key_ids"; then
         g_key_ids=$b_id
         g_key_body=$b_line
      else
         g_key_ids="${g_key_ids}
${b_id}"
         g_key_body="${g_key_body}
${b_line}"
      fi
   done < "$g_tmp_keys"
   if test -z "$g_key_body"; then
      printf 'ssh-sync-ak: no public keys in %s\n' "$g_keys_src" >&2
      exit 1
   fi
}

fn_rewrite() {
   b_skip=0
   b_found=0
   if test -f "$g_auth_file"; then
      while IFS= read -r b_line || test -n "$b_line"; do
         b_line=$(printf '%s' "$b_line" | tr -d '\r')
         if test "$b_line" = "$g_begin"; then
            if test "$b_found" -eq 0; then
               fn_print_block
               b_found=1
            fi
            b_skip=1
            continue
         fi
         if test "$b_skip" -eq 1; then
            if test "$b_line" = "$g_end"; then
               b_skip=0
            fi
            continue
         fi
         if fn_line_is_owned "$b_line"; then
            continue
         fi
         printf '%s\n' "$b_line"
      done < "$g_auth_file"
   fi
   if test "$b_found" -eq 0; then
      fn_print_block
   fi
}

fn_parse_args() {
   while test $# -gt 0; do
      case $1 in
         -h | --help)
            fn_usage
            exit 0
            ;;
         -n | --dry-run)
            g_dry_run=1
            shift
            ;;
         -f | --file)
            if test $# -lt 2; then
               printf 'ssh-sync-ak: %s needs a path\n' "$1" >&2
               exit 1
            fi
            g_auth_file=$2
            shift 2
            ;;
         --file=*)
            g_auth_file=${1#--file=}
            shift
            ;;
         --)
            shift
            break
            ;;
         -*)
            printf 'ssh-sync-ak: unknown option %s\n' "$1" >&2
            fn_usage
            exit 1
            ;;
         *)
            break
            ;;
      esac
   done

   if test $# -lt 1; then
      fn_usage
      exit 1
   fi

   g_keys_src=$1
   g_name=${2:-default}
   if test -z "$g_auth_file"; then
      g_auth_file="${SSH_AK_FILE:-${HOME}/.ssh/authorized_keys}"
   fi
}

fn_show_diff() {
   if test -f "$g_auth_file"; then
      diff -c "$g_auth_file" "$g_tmp_auth" || true
   else
      cat "$g_tmp_auth"
   fi
}

fn_main() {
   fn_parse_args "$@"

   case $g_name in
      *[!A-Za-z0-9._-]* | '')
         printf 'ssh-sync-ak: name must be A-Za-z0-9._- (got %s)\n' "$g_name" >&2
         exit 1
         ;;
   esac

   g_begin="# BEGIN ssh-sync-ak ${g_name}"
   g_end="# END ssh-sync-ak ${g_name}"

   g_ssh_dir=$(dirname "$g_auth_file")
   mkdir -p "$g_ssh_dir"
   if test "$g_dry_run" -eq 0 && test "$(basename "$g_ssh_dir")" = .ssh; then
      chmod 700 "$g_ssh_dir"
   fi

   umask 077
   g_tmp_auth="${g_auth_file}.tmp.$$"
   g_tmp_keys="${g_auth_file}.keys.$$"
   trap 'rm -f "$g_tmp_auth" "$g_tmp_keys"' EXIT

   fn_fetch_keys "$g_keys_src" > "$g_tmp_keys"
   fn_collect_keys
   g_updated="# updated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   fn_rewrite > "$g_tmp_auth"

   if test -f "$g_auth_file" && cmp -s "$g_auth_file" "$g_tmp_auth"; then
      if test "$g_dry_run" -eq 0; then
         chmod 600 "$g_auth_file"
      fi
      printf 'ssh-sync-ak: already up to date (%s in %s)\n' "$g_name" "$g_auth_file" >&2
      rm -f "$g_tmp_auth"
      return 0
   fi

   if test "$g_dry_run" -eq 1; then
      printf 'ssh-sync-ak: dry run; would write block %s to %s\n' "$g_name" "$g_auth_file" >&2
      fn_show_diff
      rm -f "$g_tmp_auth"
      return 0
   fi

   mv "$g_tmp_auth" "$g_auth_file"
   chmod 600 "$g_auth_file"
   printf 'ssh-sync-ak: wrote block %s to %s\n' "$g_name" "$g_auth_file" >&2
}

fn_main "$@"
