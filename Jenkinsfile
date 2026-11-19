pipeline {
    agent any

    environment {
        REGISTRY = 'ghcr.io'
        IMAGE_BACKEND = 'ghcr.io/adi-git-hub/devops-fullstack-backend'
        IMAGE_FRONTEND = 'ghcr.io/adi-git-hub/devops-fullstack-frontend'
        GHCR_CREDS = credentials('github-container-registry')
        EC2_HOST = credentials('ec2-host-ip')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    echo "Building Backend Docker image..."
                    sh "docker build -t ${IMAGE_BACKEND}:latest -t ${IMAGE_BACKEND}:${BUILD_NUMBER} ./backend"

                    echo "Building Frontend Docker image with relative API base..."
                    sh "docker build --build-arg VITE_API_BASE_URL=\"\" -t ${IMAGE_FRONTEND}:latest -t ${IMAGE_FRONTEND}:${BUILD_NUMBER} ./frontend"
                }
            }
        }

        stage('Push to GHCR') {
            steps {
                script {
                    echo "Authenticating with GHCR..."
                    sh "echo \$GHCR_CREDS_PSW | docker login ghcr.io -u \$GHCR_CREDS_USR --password-stdin"

                    echo "Pushing images..."
                    sh "docker push ${IMAGE_BACKEND}:latest"
                    sh "docker push ${IMAGE_BACKEND}:${BUILD_NUMBER}"
                    sh "docker push ${IMAGE_FRONTEND}:latest"
                    sh "docker push ${IMAGE_FRONTEND}:${BUILD_NUMBER}"
                }
            }
        }

        stage('Deploy to EC2 via SSH') {
            steps {
                sshagent(['ec2-ssh-key']) {
                    sh '''
                        scp -o StrictHostKeyChecking=no docker-compose.prod.yml ubuntu@${EC2_HOST}:/home/ubuntu/app/docker-compose.yml
                        ssh -o StrictHostKeyChecking=no ubuntu@${EC2_HOST} << 'EOF'
                            set -e
                            cd /home/ubuntu/app

                            if [ ! -f .env ]; then
                                cat << 'ENVFILE' > .env
DEBUG=False
SECRET_KEY=prod-secret-key-jenkins-autogen
ALLOWED_HOSTS=*
CORS_ALLOWED_ORIGINS=http://localhost,http://127.0.0.1
CORS_ALLOW_ALL_ORIGINS=True
ENVFILE
                            fi

                            docker compose pull
                            docker compose up -d --remove-orphans
                            sleep 6
                            curl -sf http://localhost/api/hello/
                            echo "Jenkins deployment successfully verified!"
EOF
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout ghcr.io || true'
        }
        success {
            echo "CI/CD Pipeline executed successfully!"
        }
        failure {
            echo "Pipeline execution failed. Check build logs for details."
        }
    }
}
