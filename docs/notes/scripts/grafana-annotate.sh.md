# `scripts/grafana-annotate.sh`

**What it does:** Posts an **annotation** (a vertical marker with text) to Grafana's HTTP API, e.g.
"Release build-15: traffic blue -> green". The dashboard shows every annotation tagged
`splitease`, so you can see *when* a release or rollback happened next to the CPU, traffic and error
graphs.

**Used by:** the *Switch traffic* stage in `Jenkinsfile` and the rollback job, with the token from
the Jenkins credential `grafana-api-token` (a Grafana service-account token). Jenkins reaches
Grafana at `http://grafana:3000`, its name on the shared docker compose network.

**The key rule: it can never fail a release.**
- The script **always exits 0**. With no token, a wrong token (HTTP 401) or Grafana down (HTTP 000),
  it prints why the annotation was skipped and carries on.
- In the Jenkinsfile the call is also wrapped in `catchError(buildResult: 'SUCCESS', stageResult:
  'SUCCESS')`. Even if the credential doesn't exist at all, the stage stays green.

Tested against a real Grafana in all four cases (valid / missing / wrong token / unreachable):
every case exited 0, and the valid one created the annotation.

`jq` builds the JSON body, so text containing quotes can't break it.
