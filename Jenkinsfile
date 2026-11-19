pipeline {
    agent any

    environment {
        REGISTRY = 'ghcr.io'
        IMAGE_BACKEND = 'ghcr.io/adi-git-hub/devops-fullstack-backend'
        IMAGE_FRONTEND = 'ghcr.io/adi-git-hub/devops-fullstack-frontend'
        EC2_HOST = "${env.EC2_HOST ?: '54.253.181.175'}"
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
                withCredentials([usernamePassword(credentialsId: 'github-container-registry', usernameVariable: 'GHCR_USER', passwordVariable: 'GHCR_TOKEN')]) {
                    sh '''
                        echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
                        docker push ${IMAGE_BACKEND}:latest
                        docker push ${IMAGE_BACKEND}:${BUILD_NUMBER}
                        docker push ${IMAGE_FRONTEND}:latest
                        docker push ${IMAGE_FRONTEND}:${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Deploy to EC2 via SSH') {
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')
                ]) {
                    sh '''
                        set -e
                        echo "Copying docker-compose.prod.yml to ubuntu@${EC2_HOST}..."
                        scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no docker-compose.prod.yml ubuntu@${EC2_HOST}:/home/ubuntu/app/docker-compose.yml

                        echo "Executing deployment on EC2..."
                        ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${EC2_HOST} << 'EOF'
                            set -e
                            cd /home/ubuntu/app

                            # Ensure .env exists with production safe defaults
                            if [ ! -f .env ]; then
                                cat << 'ENVFILE' > .env
DEBUG=False
SECRET_KEY=prod-secret-key-$(openssl rand -hex 16 2>/dev/null || echo "jenkins-auto-secret-key-12345")
ALLOWED_HOSTS=*
CORS_ALLOWED_ORIGINS=http://localhost,http://127.0.0.1
CORS_ALLOW_ALL_ORIGINS=True
ENVFILE
                            fi

                            # Pull latest images from GHCR
                            docker compose pull

                            # Start containers
                            docker compose up -d --remove-orphans

                            # Verify health
                            echo "Waiting for services to become healthy..."
                            sleep 6
                            curl -sf http://localhost/api/hello/
                            echo "Deployment successfully verified on EC2!"
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
            echo "Jenkins Pipeline executed successfully!"
        }
        failure {
            echo "Jenkins Pipeline failed. Please check build logs."
        }
    }
}
