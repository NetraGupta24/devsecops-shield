# `ansible/playbooks/deploy.yml`

**What it does:** Deploys the image recorded in SSM to **every running instance of one colour**.
Jenkins runs it in the *Deploy to idle colour* stage:
```
ansible-playbook playbooks/deploy.yml -e target_color=green -e ecr_repository_url=... --private-key <key>
```

**Steps per instance:**
1. Read `image_tag` and `chaos_mode` from SSM (the same source of truth user data uses).
2. Log in to ECR (`no_log: true`, so the token is never printed), pull the image, log out.
3. Compare with the running container. Replace it only if the image or chaos flag differs
   (**idempotent**: a second run changes nothing).
4. Start the container with exactly the same settings as user data (`--restart unless-stopped`,
   awslogs).
5. Wait for `http://127.0.0.1:5000/health`, then check `/version` shows the **expected build
   number**. A mismatch fails the deploy.
6. `docker image prune` removes old images to save disk.

**Exit codes Jenkins cares about:** 0 = OK, 2 = a task failed (pipeline fails), 4 = a host was
unreachable. Code 4 usually means the ASG is replacing that instance right now. Its replacement boots
the new version from SSM, so Jenkins lets the health-check stage decide.
