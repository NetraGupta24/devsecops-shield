# `Jenkinsfile.rollback`

**What it does:** The **rollback job** (`splitease-rollback`, started by hand).
1. **Current state:** shows what runs where. The target is the *other* colour, which still runs the
   previous release. It refuses if that colour never had a release.
2. **Check previous colour is healthy:** never switches users to an unhealthy colour.
3. **Switch traffic back:** the same `bluegreen.sh switch` the pipeline uses (port 80 ↔ 8080, SSM
   updated).
4. **Verify:** port 80 `/version` returns the previous build.

**Why it's fast:** nothing is rebuilt or redeployed, because the old version never stopped running.
That is the main benefit of Blue-Green over redeploying the old version.
