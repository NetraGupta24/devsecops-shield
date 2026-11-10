# `ansible/playbooks/configure.yml`

**What it does:** Prepares the instances of one colour (`-e target_color=blue`):
1. Checks the colour is `blue` or `green`.
2. **Waits for cloud-init** (user data) to finish. A brand-new instance may still be installing
   Docker, and two package installs at once would clash.
3. Applies the **`docker` role**: Docker installed, running and enabled.

`deploy.yml` imports this playbook first, so every deploy also guarantees the servers are configured.
