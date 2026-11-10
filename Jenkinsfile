// DevSecOps Shield - CI/CD pipeline for SplitEase.
// Build -> Test -> Secure -> Containerize -> Scan
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 45, unit: 'MINUTES')
    }

    // Jenkins runs on localhost, so GitHub cannot call it (no webhooks).
    // Instead Jenkins asks GitHub for new commits every ~2 minutes.
    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        IMAGE_NAME = 'splitease'
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --format="Commit %h by %an: %s"'
            }
        }

        stage('Unit tests') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet --disable-pip-version-check -r app/requirements-dev.txt
                    mkdir -p reports
                    cd app && pytest -v --junitxml=../reports/pytest.xml
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/pytest.xml'
                }
            }
        }

        stage('Gitleaks (secret scan)') {
            steps {
                // Scans every commit reachable from this branch (full history),
                // --redact stops the secret itself being printed in the log.
                sh 'gitleaks git --redact --verbose --log-opts="HEAD" .'
            }
        }

        stage('Docker build') {
            steps {
                // --pull always fetches the newest patched base image.
                sh 'docker build --pull --build-arg BUILD_NUMBER=${BUILD_NUMBER} -t ${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }

        stage('Trivy (image scan)') {
            steps {
                // Policy: fail on HIGH/CRITICAL vulnerabilities that have a fix.
                // See security/trivy-policy.md
                sh '''
                    trivy image --image-src docker --scanners vuln \
                        --severity HIGH,CRITICAL --ignore-unfixed \
                        --exit-code 1 --no-progress --skip-version-check \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }
    }

    post {
        always {
            // Remove the local image so the laptop's disk doesn't fill up.
            sh 'docker image rm ${IMAGE_NAME}:${IMAGE_TAG} >/dev/null 2>&1 || true'
        }
    }
}
