# `.dockerignore`

**What it does:** Decides which files are sent to Docker when building the image (the "build
context"). It uses an **allow-list**: ignore everything (`*`) and then allow only `app/`. Inside
`app/`, it also excludes the tests and Python caches.

**Why it matters:**
- **Security:** `.git` history, Terraform state, `terraform.tfvars` and keys can never end up
  inside the image.
- **Speed and size:** less data to send and a smaller image.

**How it connects:** Works together with the `Dockerfile`'s `COPY app/ .` line.
