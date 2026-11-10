# `jenkins/init.groovy.d/executors.groovy`

**What it does:** A Groovy script that Jenkins runs at every start-up. It sets the number of
*executors* (build slots) to 1.

**Why:** On a laptop, one build at a time keeps CPU and RAM usage low. It also prevents two builds
from tagging, scanning or deploying at the same moment, which matters because a deploy changes the
shared ALB listeners and SSM parameters. A rollback started during a pipeline run simply waits in
the queue.
