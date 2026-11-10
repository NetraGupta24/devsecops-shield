// DevSecOps Shield - CI/CD pipeline for SplitEase.
// Build -> Test -> Secure -> Containerize -> Scan -> Store -> Deploy -> Verify -> Switch Traffic
//
// Every branch runs the CI stages (tests, Gitleaks, Docker build, Trivy).
// Only the main branch continues to the release stages (ECR push + Blue-Green deploy).
// If ANY stage fails, the production listener (port 80) is never touched.
pipeline {
    agent any

    options {
        skipDefaultCheckout()
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
    }

    // Trigger: Jenkins runs on localhost, so GitHub cannot call it (no
    // webhooks). Instead the multibranch job "splitease" polls GitHub every
    // minute (branch indexing, see jenkins/jobs/splitease/config.xml) and
    // builds any branch whose latest commit changed. There is deliberately NO
    // pollSCM() here as well: two polling mechanisms started two builds for
    // the same commit, and on main a second release would flip traffic again.

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        IMAGE_NAME         = 'splitease'
        IMAGE_TAG          = "build-${env.BUILD_NUMBER}"
    }

    stages {
        // ------------------------------------------------------------ CI ---
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
                // Scans every commit reachable from this branch (full history).
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

        // ------------------------------------------------------- Release ---
        stage('Release (main branch only)') {
            when {
                branch 'main'
            }
            environment {
                // Jenkins IAM user keys, stored ONLY in Jenkins Credentials
                // (Secret text). Jenkins masks them in the console log.
                AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
                AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
            }
            stages {
                stage('Push to ECR') {
                    steps {
                        script {
                            def account = sh(returnStdout: true, script: 'aws sts get-caller-identity --query Account --output text').trim()
                            env.ECR_REGISTRY = "${account}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com"
                            env.ECR_REPO = "${env.ECR_REGISTRY}/${env.IMAGE_NAME}"
                        }
                        sh '''
                            aws ecr get-login-password | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
                            docker push ${ECR_REPO}:${IMAGE_TAG}
                            docker logout ${ECR_REGISTRY}
                        '''
                    }
                }

                stage('Find idle colour') {
                    steps {
                        script {
                            env.LIVE_COLOR = sh(returnStdout: true, script: './scripts/bluegreen.sh live-color').trim()
                            env.IDLE_COLOR = sh(returnStdout: true, script: "./scripts/bluegreen.sh other-color ${env.LIVE_COLOR}").trim()
                            env.PREVIOUS_IDLE_TAG = sh(returnStdout: true, script: "./scripts/bluegreen.sh get-tag ${env.IDLE_COLOR}").trim()
                            echo "Live colour: ${env.LIVE_COLOR}. Deploying ${env.IMAGE_TAG} to idle colour: ${env.IDLE_COLOR} (currently ${env.PREVIOUS_IDLE_TAG})"
                        }
                    }
                }

                stage('Deploy to idle colour') {
                    steps {
                        // 1) Record the new version in SSM, so any instance the ASG
                        //    launches from now on boots this version (user data).
                        sh './scripts/bluegreen.sh set-tag ${IDLE_COLOR} ${IMAGE_TAG}'
                        script { env.TAG_UPDATED = 'true' }
                        // 2) Ansible updates the instances that are already running.
                        withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                            dir('ansible') {
                                sh '''#!/bin/bash
                                    # A key pasted into the Jenkins web form can arrive with Windows
                                    # line endings (CRLF) and/or without its final newline; OpenSSH
                                    # then refuses it ("Load key: error in libcrypto"). Use a cleaned
                                    # copy in a private temp folder that is deleted when this step ends.
                                    KEY_DIR="$(mktemp -d)"
                                    trap 'rm -rf "$KEY_DIR"' EXIT
                                    tr -d '\\r' < "$SSH_KEY_FILE" > "$KEY_DIR/key"
                                    if [ -n "$(tail -c1 "$KEY_DIR/key")" ]; then echo >> "$KEY_DIR/key"; fi
                                    chmod 600 "$KEY_DIR/key"

                                    set +e
                                    ansible-playbook playbooks/deploy.yml \
                                        --private-key "$KEY_DIR/key" --user "$SSH_USER" \
                                        -e target_color=${IDLE_COLOR} -e ecr_repository_url=${ECR_REPO}
                                    rc=$?
                                    # rc 4 = some hosts were unreachable (typically an instance the
                                    # Auto Scaling Group is replacing right now). Its replacement
                                    # boots the new version from SSM, and the next stage's health
                                    # check is the real gate, so don't fail here.
                                    if [ $rc -eq 4 ]; then
                                        echo "WARNING: some instances were unreachable; relying on user data + health check."
                                        exit 0
                                    fi
                                    exit $rc
                                '''
                            }
                        }
                    }
                }

                stage('Health check (idle colour)') {
                    steps {
                        // a) every target of the idle colour passes the ALB /health check
                        sh './scripts/bluegreen.sh wait-healthy ${IDLE_COLOR} 900'
                        // b) the TEST listener (8080 -> idle colour) really serves the NEW build
                        sh './scripts/bluegreen.sh check-version 8080 ${BUILD_NUMBER}'
                    }
                }

                stage('Switch traffic') {
                    steps {
                        sh './scripts/bluegreen.sh switch ${IDLE_COLOR}'
                        script { env.SWITCHED = 'true' }
                        sh './scripts/bluegreen.sh check-version 80 ${BUILD_NUMBER}'
                        // First release only: the old colour has never run anything.
                        // Give it this release too, so its instances (replaced by the
                        // ASG) become healthy and rollback has a working target.
                        sh '''
                            if [ "$(./scripts/bluegreen.sh get-tag ${LIVE_COLOR})" = "none" ]; then
                                ./scripts/bluegreen.sh set-tag ${LIVE_COLOR} ${IMAGE_TAG}
                            fi
                        '''
                    }
                }
            }
            post {
                unsuccessful {
                    script {
                        if (env.TAG_UPDATED == 'true' && env.SWITCHED != 'true') {
                            // The release failed before the switch: put the idle colour's
                            // SSM tag back, so replacement instances boot the last good
                            // version. Production (port 80) was never changed.
                            sh './scripts/bluegreen.sh set-tag ${IDLE_COLOR} ${PREVIOUS_IDLE_TAG}'
                            echo "Release failed. Live colour ${env.LIVE_COLOR} was NOT touched and is still serving users."
                        }
                    }
                }
                success {
                    sh './scripts/bluegreen.sh status'
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.SWITCHED == 'true') {
                    echo "RELEASED: ${env.IMAGE_TAG} is live on ${env.IDLE_COLOR}. Previous colour ${env.LIVE_COLOR} kept for rollback."
                } else {
                    echo "CI passed for branch ${env.BRANCH_NAME} (release stages run on main only)."
                }
            }
        }
        always {
            // Remove local images so the laptop's disk doesn't fill up.
            sh '''
                docker image rm ${IMAGE_NAME}:${IMAGE_TAG} >/dev/null 2>&1 || true
                if [ -n "${ECR_REPO:-}" ]; then docker image rm ${ECR_REPO}:${IMAGE_TAG} >/dev/null 2>&1 || true; fi
            '''
        }
    }
}
