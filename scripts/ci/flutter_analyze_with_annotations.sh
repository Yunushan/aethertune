#!/usr/bin/env bash
set -uo pipefail

log_file="${1:-flutter-analyze.log}"

set +e
flutter analyze >"${log_file}" 2>&1
status=$?
set -e

cat "${log_file}"

if [[ ${status} -ne 0 ]]; then
  awk -F ' • ' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    function escape(value) {
      gsub(/%/, "%25", value)
      gsub(/\r/, "%0D", value)
      gsub(/\n/, "%0A", value)
      return value
    }

    /^[[:space:]]*(error|warning|info)[[:space:]]*•/ {
      level = trim($1)
      split($3, location, ":")
      command = level == "info" ? "notice" : level
      title = escape($4)
      message = escape($2)
      printf("::%s file=%s,line=%s,col=%s,title=%s::%s\n",
        command,
        location[1],
        location[2],
        location[3],
        title,
        message)
    }
  ' "${log_file}"
fi

exit "${status}"
