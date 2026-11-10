// Runs every time Jenkins starts.
// One executor = one build at a time. On a laptop this keeps CPU/RAM usage
// low, and it stops two builds from building/scanning Docker images (or
// switching ALB listeners) at the same moment.
import jenkins.model.Jenkins

Jenkins.get().setNumExecutors(1)
