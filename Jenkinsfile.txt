pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        AWS_REGION    = 'us-east-1'
        AWS_ACCOUNT_ID = '881776924457'
        ECR_REPOSITORY = 'demo-microservice'
        EKS_CLUSTER    = 'demo-eks-cluster'
        K8S_NAMESPACE  = 'demo'
        HELM_RELEASE   = 'demo-microservice'
        HELM_CHART     = 'helm/microservice'
        KUBECONFIG     = '/var/lib/jenkins/.kube/config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHA}"

                    echo "Git commit: ${env.GIT_SHA}"
                    echo "Docker image tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Validate Files') {
            steps {
                sh '''
                    set -eu

                    test -f app/Dockerfile
                    test -f app/app.py
                    test -f app/requirements.txt
                    test -f helm/microservice/Chart.yaml
                    test -f helm/microservice/values.yaml
                    test -f helm/microservice/templates/deployment.yaml
                    test -f helm/microservice/templates/service.yaml

                    helm lint helm/microservice
                '''
            }
        }

        stage('Verify AWS Access') {
            steps {
                sh '''
                    set -eu

                    aws sts get-caller-identity

                    aws ecr describe-repositories \
                      --region "$AWS_REGION" \
                      --repository-names "$ECR_REPOSITORY"
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -eu

                    docker build \
                      -t "$ECR_REPOSITORY:$IMAGE_TAG" \
                      ./app
                '''
            }
        }

        stage('Push Image to ECR') {
            steps {
                sh '''
                    set -eu

                    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

                    aws ecr get-login-password --region "$AWS_REGION" |
                      docker login \
                        --username AWS \
                        --password-stdin "$ECR_REGISTRY"

                    docker tag "$ECR_REPOSITORY:$IMAGE_TAG" "$IMAGE_URI"
                    docker push "$IMAGE_URI"

                    echo "Published image: $IMAGE_URI"
                '''
            }
        }

        stage('Deploy to EKS with Helm') {
            steps {
                sh '''
                    set -eu

                    test -f "$KUBECONFIG"

                    aws eks describe-cluster \
                      --region "$AWS_REGION" \
                      --name "$EKS_CLUSTER" \
                      --query 'cluster.status' \
                      --output text

                    helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
                      --kubeconfig "$KUBECONFIG" \
                      --namespace "$K8S_NAMESPACE" \
                      --set replicaCount=1 \
                      --set image.repository="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}" \
                      --set-string image.tag="$IMAGE_TAG" \
                      --wait \
                      --timeout 5m
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -eu

                    kubectl --kubeconfig "$KUBECONFIG" \
                      rollout status deployment/"$HELM_RELEASE" \
                      --namespace "$K8S_NAMESPACE" \
                      --timeout=180s

                    kubectl --kubeconfig "$KUBECONFIG" \
                      get deployment,pods,service \
                      --namespace "$K8S_NAMESPACE"

                    kubectl --kubeconfig "$KUBECONFIG" \
                      get deployment "$HELM_RELEASE" \
                      --namespace "$K8S_NAMESPACE" \
                      -o jsonpath='{.spec.template.spec.containers[0].image}'

                    echo
                '''
            }
        }
    }

    post {
        success {
            echo 'CI/CD pipeline completed successfully.'
        }

        failure {
            echo 'CI/CD pipeline failed. Review the failed stage and console output.'
        }
    }
}