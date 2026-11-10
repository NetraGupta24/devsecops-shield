# `jenkins/jobs/splitease-rollback/config.xml`

**What it does:** Defines the job **`splitease-rollback`**: a normal Pipeline job that runs
`Jenkinsfile.rollback` from the `main` branch. It has no trigger, so you start it by hand with
"Build Now" when a release turns out to be bad. It swaps production traffic back to the previous
colour in a few seconds, without rebuilding anything.
