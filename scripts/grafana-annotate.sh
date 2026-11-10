#!/usr/bin/env bash
# Post an annotation (a vertical marker) to Grafana, e.g. "Release build-14: blue -> green".
# Used by Jenkinsfile (after a traffic switch) and Jenkinsfile.rollback.
#
#   grafana-annotate.sh "<text>" [extra-tag ...]
#
# Environment:
#   GRAFANA_TOKEN  service-account token (from the Jenkins credential 'grafana-api-token')
#   GRAFANA_URL    default http://grafana:3000 (Grafana's name on the docker compose network)
#
# Monitoring must NEVER break a release: this script always exits 0. If Grafana is down,
# the token is missing or wrong, it prints why the annotation was skipped and carries on.
# (No "set -e" on purpose.)

TEXT="${1:-SplitEase event}"
shift || true
URL="${GRAFANA_URL:-http://grafana:3000}"

if [ -z "${GRAFANA_TOKEN:-}" ]; then
  echo "Grafana annotation skipped: no GRAFANA_TOKEN (release is unaffected)."
  exit 0
fi

# Tags: always "splitease" (the dashboard shows every annotation with that tag) + extras.
TAGS="$(printf '%s\n' splitease "$@" | jq -R . | jq -sc .)"
BODY="$(jq -nc --arg text "$TEXT" --argjson tags "$TAGS" '{text: $text, tags: $tags}')"

CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -X POST "$URL/api/annotations" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$BODY")" || CODE="000"

if [ "$CODE" = "200" ]; then
  echo "Grafana annotation added: $TEXT"
else
  echo "Grafana annotation skipped (HTTP $CODE from $URL); the release itself is unaffected."
fi
exit 0
