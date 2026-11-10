# `security/trivy-policy.md`

**What it is:** The written rule for Security Gate 2. It covers what Trivy blocks (HIGH/CRITICAL
with a fix), what it doesn't block and why, how we fix findings, and how exceptions would be
handled.

**Why it's needed:** A security gate needs a documented policy. Otherwise nobody knows why a build
failed, or whether it is acceptable to bypass. It also records the evidence from our own scans.
