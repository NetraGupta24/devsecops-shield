"""Payment gateway settings.

DEMO (failure demo 3): the key below is FAKE. It was committed on purpose to
prove that Gitleaks (Security Gate 1) finds secrets in the git history and
stops the pipeline. Real secrets belong in a secret store, never in code.
"""

PAYMENT_GATEWAY_URL = "https://payments.example.invalid/v1"
PAYMENT_GATEWAY_API_KEY = "fk_live_8Zq3Xv7Lp2Rt9Wm4Ns6Bd1Hc5Jy0KeQ"
