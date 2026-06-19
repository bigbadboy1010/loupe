#!/usr/bin/env bash
# Append Sprint-1 env vars to /opt/loupe/Loupe/loupe-signaling/.env
# Idempotent: removes any previous Sprint-1 block first.

set -euo pipefail

REPO=/opt/loupe/Loupe/loupe-signaling
ENV_FILE="$REPO/.env"
TOKEN_FILE=/tmp/loupe-admin-token

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "ERROR: $TOKEN_FILE missing. Run token generation first." >&2
  exit 2
fi

TOKEN=$(cat "$TOKEN_FILE")
if [[ ${#TOKEN} -lt 32 ]]; then
  echo "ERROR: token in $TOKEN_FILE is too short (${#TOKEN} chars)" >&2
  exit 3
fi

# Strip any previous Sprint-1 block (between marker lines)
sudo bash -c "
  set -e
  ENV_FILE='$ENV_FILE'
  cp \"\$ENV_FILE\" \"\${ENV_FILE}.bak3-pre-append\"
  # Remove any block between '# Sprint 1 (v3.9.0' and EOF
  awk '
    /^# Sprint 1 \\(v3\\.9\\.0-landing/ { skip=1; next }
    skip && /^$/ && getline next_line && next_line !~ /^(SERVE_SITE|TURN_REALM|TURN_EXTERNAL_IP|WAITLIST_ADMIN_TOKEN)/ { skip=0; print; print next_line; next }
    skip && /^(SERVE_SITE|TURN_REALM|TURN_EXTERNAL_IP|WAITLIST_ADMIN_TOKEN)/ { next }
    skip && /^$/ { next }
    skip { skip=0 }
    { print }
  ' \"\$ENV_FILE\" > \"\${ENV_FILE}.tmp\"
  mv \"\${ENV_FILE}.tmp\" \"\${ENV_FILE}\"
  printf '\n# Sprint 1 (v3.9.0-landing-public) additions\n' >> \"\$ENV_FILE\"
  echo 'SERVE_SITE=true' >> \"\$ENV_FILE\"
  echo 'TURN_REALM=loupe.ddns.net' >> \"\$ENV_FILE\"
  echo 'TURN_EXTERNAL_IP=212.186.18.125' >> \"\$ENV_FILE\"
  printf 'WAITLIST_ADMIN_TOKEN=%s\n' \"\$TOKEN\" >> \"\$ENV_FILE\"
  chown miggu69:miggu69 \"\$ENV_FILE\"
  chmod 640 \"\$ENV_FILE\"
"

echo "OK"
echo "--- new .env (redacted) ---"
sed -E 's/(=.{0,4}).*/\1***REDACTED***/' "$ENV_FILE"
