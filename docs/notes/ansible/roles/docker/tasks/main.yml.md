# `ansible/roles/docker/tasks/main.yml`

**What it does:** The `docker` **role**, a reusable bundle of tasks:
1. Check whether `/usr/bin/docker` exists.
2. If not, install it with `dnf`. Skipping dnf when Docker is present keeps deploys fast on a small
   t3.micro.
3. Make sure the Docker service is running and starts at boot.
4. Add `ec2-user` to the `docker` group (so you can run `docker ps` when you SSH in).

**Why a role:** roles keep playbooks short and let several playbooks reuse the same setup.
