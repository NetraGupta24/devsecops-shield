#!/usr/bin/env bash
# Blue-Green helper commands, shared by Jenkinsfile and Jenkinsfile.rollback.
# Uses the AWS CLI (credentials come from Jenkins as environment variables).
#
#   bluegreen.sh live-color                     print the live colour (from SSM)
#   bluegreen.sh other-color <colour>           print the opposite colour
#   bluegreen.sh get-tag <colour>               print the image tag a colour runs (from SSM)
#   bluegreen.sh set-tag <colour> <tag>         record the image tag for a colour in SSM
#   bluegreen.sh wait-healthy <colour> [secs]   wait until every target of that colour is healthy
#   bluegreen.sh check-version <port> <build>   check /version through the ALB returns <build>
#   bluegreen.sh switch <new-live-colour>       port 80 -> new colour, port 8080 -> old colour, update SSM
#   bluegreen.sh status                         print what runs where
set -euo pipefail

PROJECT="${PROJECT:-splitease}"
ALB_NAME="${ALB_NAME:-${PROJECT}-alb}"
PARAM_PREFIX="/${PROJECT}"

die() { echo "ERROR: $*" >&2; exit 1; }

valid_color() { [[ "$1" == "blue" || "$1" == "green" ]] || die "colour must be blue or green, got '$1'"; }

other_color() { valid_color "$1"; if [[ "$1" == "blue" ]]; then echo green; else echo blue; fi; }

get_param() { aws ssm get-parameter --name "$1" --query Parameter.Value --output text; }

put_param() { aws ssm put-parameter --name "$1" --value "$2" --type String --overwrite >/dev/null; }

alb_arn() {
  aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text
}

alb_dns() {
  aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].DNSName' --output text
}

listener_arn() { # $1 = port
  aws elbv2 describe-listeners --load-balancer-arn "$(alb_arn)" \
    --query "Listeners[?Port==\`$1\`].ListenerArn | [0]" --output text
}

tg_arn() { # $1 = colour
  aws elbv2 describe-target-groups --names "${PROJECT}-$1" --query 'TargetGroups[0].TargetGroupArn' --output text
}

listener_color() { # $1 = port -> which colour's target group the listener forwards to
  local forwarded
  forwarded="$(aws elbv2 describe-listeners --listener-arns "$(listener_arn "$1")" \
    --query 'Listeners[0].DefaultActions[0].TargetGroupArn' --output text)"
  case "$forwarded" in
    *"/${PROJECT}-blue/"*) echo blue ;;
    *"/${PROJECT}-green/"*) echo green ;;
    *) echo unknown ;;
  esac
}

cmd_live_color() {
  local live
  live="$(get_param "$PARAM_PREFIX/live_color")"
  valid_color "$live"
  echo "$live"
}

cmd_wait_healthy() { # $1 = colour, $2 = timeout seconds (default 900), $3 = required healthy polls (default 5)
  local color="$1" timeout="${2:-900}" required="${3:-5}" waited=0 bad_answers=0 streak=0 arn states
  valid_color "$color"
  arn="$(tg_arn "$color")"
  # Why "N healthy polls in a row" and not "healthy once": right after Ansible
  # replaces a container, the ALB still shows the OLD container's "healthy"
  # status. It needs unhealthy_threshold x interval = 3 x 15 s = 45 s to notice
  # a bad new container. 5 polls 15 s apart (60 s) covers that window.
  echo "Waiting up to ${timeout}s for every ${color} target to be healthy for ${required} checks in a row..."
  while true; do
    # One line per target: <instance-id> <state> <reason>. Draining targets
    # (being removed by Auto Scaling) are ignored.
    states="$(aws elbv2 describe-target-health --target-group-arn "$arn" \
      --query 'TargetHealthDescriptions[?TargetHealth.State!=`draining`].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
      --output text)"
    echo "  [${waited}s] ${states:-no targets registered yet}" | tr '\n\t' '; '
    echo
    if [[ -n "$states" ]] && ! awk '{print $2}' <<<"$states" | grep -qv '^healthy$'; then
      streak=$((streak + 1))
      if (( streak >= required )); then
        echo "All ${color} targets have been healthy for ${required} checks in a row."
        return 0
      fi
    else
      streak=0
    fi
    # "ResponseCodeMismatch" = the app IS running but answers /health with an
    # error (e.g. HTTP 500): a bad release, not a slow boot. Fail after ~1 min
    # instead of waiting for the full timeout.
    if grep -q 'Target.ResponseCodeMismatch' <<<"$states"; then
      bad_answers=$((bad_answers + 1))
      if (( bad_answers >= 4 )); then
        die "${color} app answers /health with an error code (Target.ResponseCodeMismatch): bad release"
      fi
    else
      bad_answers=0
    fi
    if (( waited >= timeout )); then
      die "${color} targets did not all become healthy within ${timeout}s"
    fi
    sleep 15
    waited=$((waited + 15))
  done
}

cmd_check_version() { # $1 = listener port, $2 = expected build number
  local port="$1" expected="$2" dns url build ok=0 attempt
  dns="$(alb_dns)"
  url="http://${dns}:${port}/version"
  echo "Checking ${url} returns build ${expected} (5 answers in a row)..."
  for attempt in $(seq 1 40); do
    build="$(curl -s --max-time 5 "$url" | jq -r '.build // empty' 2>/dev/null || true)"
    if [[ "$build" == "$expected" ]]; then
      ok=$((ok + 1))
      echo "  attempt ${attempt}: build ${build} (ok ${ok}/5)"
      if (( ok >= 5 )); then
        echo "Port ${port} serves build ${expected}."
        return 0
      fi
    else
      ok=0
      echo "  attempt ${attempt}: got '${build:-no answer}', expected ${expected}"
    fi
    sleep 3
  done
  die "port ${port} did not consistently return build ${expected}"
}

cmd_switch() { # $1 = colour that becomes live
  local new_live="$1" old_live
  valid_color "$new_live"
  old_live="$(other_color "$new_live")"
  echo "Switching production traffic: ${old_live} -> ${new_live}"
  aws elbv2 modify-listener --listener-arn "$(listener_arn 80)" \
    --default-actions "Type=forward,TargetGroupArn=$(tg_arn "$new_live")" >/dev/null
  echo "  port 80   now forwards to ${new_live}"
  aws elbv2 modify-listener --listener-arn "$(listener_arn 8080)" \
    --default-actions "Type=forward,TargetGroupArn=$(tg_arn "$old_live")" >/dev/null
  echo "  port 8080 now forwards to ${old_live} (kept for rollback)"
  put_param "$PARAM_PREFIX/live_color" "$new_live"
  echo "  SSM ${PARAM_PREFIX}/live_color = ${new_live}"
}

cmd_status() {
  local live dns
  live="$(cmd_live_color)"
  dns="$(alb_dns)"
  echo "Live colour (SSM): ${live}"
  echo "Port 80   -> $(listener_color 80)"
  echo "Port 8080 -> $(listener_color 8080)"
  echo "blue  image tag: $(get_param "$PARAM_PREFIX/blue/image_tag")"
  echo "green image tag: $(get_param "$PARAM_PREFIX/green/image_tag")"
  echo "chaos_mode     : $(get_param "$PARAM_PREFIX/chaos_mode")"
  echo "Live URL       : http://${dns}/"
  echo "Live version   : $(curl -s --max-time 5 "http://${dns}/version" || echo 'no answer')"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    live-color) cmd_live_color ;;
    other-color) other_color "${1:?colour}" ;;
    get-tag) valid_color "${1:?colour}"; get_param "$PARAM_PREFIX/$1/image_tag" ;;
    set-tag) valid_color "${1:?colour}"; put_param "$PARAM_PREFIX/$1/image_tag" "${2:?tag}"; echo "SSM ${PARAM_PREFIX}/$1/image_tag = $2" ;;
    wait-healthy) cmd_wait_healthy "${1:?colour}" "${2:-900}" "${3:-5}" ;;
    check-version) cmd_check_version "${1:?port}" "${2:?build}" ;;
    switch) cmd_switch "${1:?colour}" ;;
    status) cmd_status ;;
    alb-dns) alb_dns ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
  esac
}

main "$@"
