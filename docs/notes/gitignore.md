# `.gitignore`

**What it does:** Tells Git which files must never be committed.

**Why it's needed:** Some files are generated (Python caches, the `.venv` virtual environment, test
reports), and some are dangerous to publish:
- `*.tfstate`: Terraform state can contain resource details and sometimes secrets.
- `terraform.tfvars`: holds your real IP address and email.
- `*.pem`, `*.key`, `id_ed25519*`: private keys.

**How it connects:** Gitleaks (Security Gate 1) catches secrets that slip into commits. `.gitignore`
is the first line of defence that stops them being committed at all.
`terraform/.terraform.lock.hcl` is *not* ignored because it pins the exact provider versions.
