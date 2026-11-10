# `jenkins/jobs/splitease/config.xml`

**What it does:** Defines the Jenkins job **`splitease`** as code. It is a **Multibranch Pipeline**:
- Source: the GitHub repository (`<remote>`).
- **Every minute** (`PeriodicFolderTrigger`) Jenkins asks GitHub which branches exist and what their
  latest commit is. New branches get their own sub-job automatically, and new commits are built.
  This is how "Poll SCM" works for a multibranch job, and it is the *only* trigger. A second
  `pollSCM` in the Jenkinsfile caused duplicate builds of the same commit, so it was removed.
- Each branch runs the `Jenkinsfile` of that branch.

**Why multibranch:** the failure demos live on their own branches (`demo/fake-secret`, ...). A
multibranch job builds them without touching `main`. The `Jenkinsfile` makes sure **only `main`**
is pushed to ECR and deployed, as in a real team.

**How it gets into Jenkins:** `jenkins/Dockerfile` copies it to
`/usr/share/jenkins/ref/jobs/splitease/config.xml.override`. Jenkins copies `ref/` into
`JENKINS_HOME` at every start, and the `.override` suffix means the copy in Git always wins.
