# `ansible/ansible.cfg`

**What it does:** Ansible's settings, used automatically when you run Ansible from `ansible/`.
- `inventory = inventory/aws_ec2.yml`: use the dynamic AWS inventory by default.
- `remote_user = ec2-user`: the default user on Amazon Linux.
- `host_key_checking = False`: instances are replaced all the time, so their SSH host keys keep
  changing (an accepted trade-off for auto-scaled servers).
- `pipelining`, `ControlPersist`: faster SSH (one connection reused for many tasks).
- `enable_plugins`: the aws_ec2 dynamic inventory plus plain host lists (for testing).

**What is Ansible?** A tool that connects to servers over SSH and makes them match a description
(a *playbook*). There's no agent to install on the servers, and it is *idempotent*: running it
twice changes nothing the second time.
