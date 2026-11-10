# `jenkins/plugins.txt`

**What it does:** The list of Jenkins plugins baked into the image.

| Plugin | Used for |
|---|---|
| workflow-aggregator | Pipeline (`Jenkinsfile`) support |
| workflow-multibranch | One job that builds every branch (needed for the demo branches) |
| git | Checking out code from GitHub, polling |
| credentials-binding | `withCredentials(...)`: injects AWS keys / the SSH key safely and masks them in logs |
| ssh-credentials | Stores the EC2 SSH private key |
| pipeline-stage-view | The coloured stage boxes on the job page (good for screenshots) |
| timestamper | Timestamps on each log line |
| junit | Shows pytest results as a test report |
| ws-cleanup | Workspace clean-up |
