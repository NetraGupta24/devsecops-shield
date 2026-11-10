# Study notes (one per file)

Each note explains, in plain English, **what a file does, why the project needs it, and how it
connects to the rest**. The folder layout mirrors the repository, so the note for
`terraform/alb.tf` is `docs/notes/terraform/alb.tf.md`.

Suggested reading order for the viva:
1. `app/` - the application and its tests
2. `Dockerfile`, `.dockerignore` - packaging the app
3. `jenkins/`, `Jenkinsfile` - the CI/CD pipeline
4. `security/` - the two security gates
5. `terraform/` - the AWS infrastructure
6. `ansible/` - deploying to the servers
7. `Jenkinsfile.rollback` - the rollback job
