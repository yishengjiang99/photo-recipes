#!/usr/bin/env bash
# Snapshot status + headers of every API route (GET only, no body, no side effects) so a deploy can
# prove API behaviour is unchanged: scripts/api-snapshot.sh https://photo.grepawk.com scripts/api-snapshot-paths.txt
# api-snapshot.sh <base> <paths-file>  -> normalized status+headers per path (GET, no body sent)
base="$1"
while read -r p; do
  [[ -z "$p" || "$p" == \#* ]] && continue
  echo "== $p"
  curl -s -o /dev/null -D - -m 20 "$base$p" | tr -d '\r' \
    | sed -E 's#^HTTP/[0-9.]+ ([0-9]{3}).*#STATUS \1#; s#^([A-Za-z0-9-]+):#\L\1:#' \
    | grep -viE '^(date|etag|last-modified|content-length|server|expires|connection|strict-transport-security|vary|x-request-id|ratelimit[a-z-]*|retry-after|set-cookie|age):' | grep -v '^$' | sort
done < "$2"
