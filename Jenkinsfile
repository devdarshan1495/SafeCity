pipeline {
    agent any

    environment {
        AWS_REGION = "ap-south-1"
        ECR = "075991854069.dkr.ecr.ap-south-1.amazonaws.com"
        API_IMAGE = "${ECR}/safecity-api"
        DASHBOARD_IMAGE = "${ECR}/safecity-dashboard"
    }

    stages {
        stage("Checkout") {
            steps {
                checkout scm
            }
        }

        stage("Test API") {
            steps {
                sh """
                    docker build -t safecity-api-test -f app/api/Dockerfile app/api/
                    docker run --rm safecity-api-test sh -c "
                        pip install -q pytest &&
                        python -m pytest tests/ -v
                    "
                """
            }
        }

        stage("Test Dashboard") {
            steps {
                sh """
                    docker build -t safecity-dashboard-test -f app/dashboard/Dockerfile app/dashboard/
                    docker run --rm safecity-dashboard-test sh -c "
                        pip install -q pytest &&
                        python -m pytest tests/ -v
                    "
                """
            }
        }

        stage("Login to ECR") {
            steps {
                sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR}"
            }
        }

        stage("Build & Push Images") {
            steps {
                sh """
                    docker build -t ${API_IMAGE}:latest -t ${API_IMAGE}:${BUILD_NUMBER} app/api/
                    docker build -t ${DASHBOARD_IMAGE}:latest -t ${DASHBOARD_IMAGE}:${BUILD_NUMBER} app/dashboard/
                    docker push ${API_IMAGE}:latest
                    docker push ${API_IMAGE}:${BUILD_NUMBER}
                    docker push ${DASHBOARD_IMAGE}:latest
                    docker push ${DASHBOARD_IMAGE}:${BUILD_NUMBER}
                """
            }
        }

        stage("Deploy to Kubernetes") {
            steps {
                sh """
                    kubectl set image deployment/safecity-api -n safecity app=${API_IMAGE}:${BUILD_NUMBER} --record
                    kubectl set image deployment/safecity-dashboard -n safecity app=${DASHBOARD_IMAGE}:${BUILD_NUMBER} --record
                    kubectl rollout status deployment/safecity-api -n safecity --timeout=120s
                    kubectl rollout status deployment/safecity-dashboard -n safecity --timeout=120s
                """
            }
        }
    }

    post {
        failure {
            echo "Pipeline failed. Check build logs."
        }
        success {
            echo "SafeCity deployment successful!"
        }
    }
}
