# `terraform/alb.tf`

**What it does:** The **Application Load Balancer**, the single public entry point.
- **Target groups `splitease-blue` and `splitease-green`:** each is a list of instances. The ALB
  checks `GET /health` every 15 s: 2 passes = healthy, 3 failures = unhealthy. Only healthy targets
  get traffic. `deregistration_delay = 30` lets in-flight requests finish for 30 s when an instance
  leaves.
- **Listener 80 (production):** forwards to the **live** colour.
- **Listener 8080 (test):** forwards to the **idle** colour, so the new version can be tested
  through the real ALB *before* users see it.

**Blue-Green switching:** Jenkins changes which target group each listener forwards to
(`ModifyListener`). That is instant and doesn't touch the servers. Because Jenkins owns that
setting, both listeners have `lifecycle { ignore_changes = [default_action] }`. Without it, the
next `terraform apply` would quietly switch traffic back.

**Security:** `drop_invalid_header_fields = true` drops malformed HTTP headers (a request-smuggling
defence).
