# AWS EKS Microservice — Jenkins CI/CD with Helm

A containerized Flask microservice deployed to Amazon Elastic Kubernetes Service (EKS), with images stored in Amazon Elastic Container Registry (ECR), deployments managed by Helm, and internet traffic routed through an AWS Application Load Balancer (ALB).

## Architecture

### Request flow

```text
                         Internet / Browser
                                 |
                                 | HTTP :80
                                 v
                 AWS Application Load Balancer (ALB)
                                 |
                                 v
                    Kubernetes Ingress
                       path: /demo
                                 |
                                 v
                    demo-microservice Service
                         ClusterIP :8080
                                 |
                                 v
                     Flask application Pod
                              :8080
                                 |
                                 v
                           HTTP response
```

### CI/CD flow

```text
Developer updates code
         |
         v
GitHub repository
         |
         v
Jenkins pipeline
  1. Checkout source
  2. Validate files and lint Helm chart
  3. Verify AWS identity and ECR access
  4. Build Docker image
  5. Push image to Amazon ECR
  6. Deploy/update with Helm on EKS
  7. Verify Kubernetes rollout
         |
         v
Amazon EKS Deployment / Pod
         |
         v
Application is served through Ingress and ALB
```

## Components

| Component | Responsibility |
|---|---|
| **GitHub** | Stores the application, Dockerfile, Helm chart, Kubernetes Ingress manifest, and Jenkins pipeline. |
| **Jenkins** | Automates validation, image build, ECR push, Helm deployment, and rollout verification. |
| **Docker** | Packages the Flask application and Python dependencies into a container image. |
| **Amazon ECR** | Stores versioned Docker images used by the EKS workload. |
| **Amazon EKS** | Runs and orchestrates the Kubernetes application. |
| **Helm** | Packages Kubernetes manifests and manages the `demo-microservice` release. |
| **AWS Load Balancer Controller** | Watches Kubernetes Ingress resources and provisions/configures the AWS ALB. |
| **AWS Application Load Balancer** | Provides the internet-facing HTTP entry point and forwards traffic to application targets. |
| **Kubernetes Ingress** | Defines routing for requests to `/demo`. |
| **Kubernetes Service** | Exposes the application internally as `demo-microservice` on port `8080` and selects matching Pods. |
| **Flask Pod** | Runs the application container and responds to HTTP requests on port `8080`. |

## Repository layout

```text
eks-microservice-project/
├── app/
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── helm/
│   └── microservice/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
├── k8s/
│   └── ingress.yaml
├── terraform/
│   └── ... infrastructure configuration ...
├── Jenkinsfile
└── README.md
```

The exact Terraform files depend on the infrastructure configuration in the repository; this README does not assume every AWS resource is managed by Terraform.

## Request lifecycle

1. A user opens the ALB URL and requests `/demo` over HTTP on port `80`.
2. The ALB forwards the request according to the routing configuration generated from the Kubernetes Ingress.
3. The Ingress rule matches `/demo` and routes the request to `demo-microservice`.
4. The ClusterIP Service forwards the request to a selected application Pod on port `8080`.
5. The Flask application returns a JSON response.
6. The response travels back through the Service, ALB, and browser.

The Flask application's `/health` endpoint is used by the Deployment's readiness and liveness probes. The ALB's own health-check configuration is managed separately through the Ingress/Load Balancer Controller configuration.

## CI/CD pipeline stages

1. **Checkout** — retrieves source from the GitHub `main` branch.
2. **Validate Files** — checks required application and Helm files and runs `helm lint`.
3. **Verify AWS Access** — checks the Jenkins EC2 instance role identity and verifies ECR repository access.
4. **Build Docker Image** — builds the image from `app/Dockerfile`.
5. **Push Image to ECR** — authenticates Docker to ECR and pushes a uniquely tagged image.
6. **Deploy to EKS with Helm** — runs `helm upgrade --install` with the new image tag.
7. **Verify Deployment** — waits for the Kubernetes rollout and prints deployment, Pod, Service, and deployed image details.

The pipeline uses the Jenkins EC2 instance's IAM role for AWS API access; long-lived AWS access keys should not be embedded in the repository or Jenkinsfile.

## Configuration details

Values confirmed in the working setup:

- AWS Region: `us-east-1`
- EKS cluster: `demo-eks-cluster`
- Kubernetes namespace: `demo`
- ECR repository: `demo-microservice`
- Helm release: `demo-microservice`
- Helm chart path: `helm/microservice`
- Application/Service port: `8080`
- Ingress application path: `/demo`
- Ingress/ALB listener: HTTP port `80`
- Image tag format used by Jenkins: `<BUILD_NUMBER>-<SHORT_GIT_SHA>`

Example image URI format:

```text
881776924457.dkr.ecr.us-east-1.amazonaws.com/demo-microservice:<tag>
```

Replace account-specific values and the ALB DNS name if recreating the project in another AWS account or region.

## Run and verify

### Check Kubernetes resources

Run from a terminal configured with access to the cluster:

```bash
kubectl get ingress -n demo
kubectl get deployment,pods,service -n demo
kubectl rollout status deployment/demo-microservice -n demo
```

### Test through the ALB

Replace `<ALB-DNS-NAME>` with the ALB hostname shown in the Ingress address:

```bash
curl -i http://<ALB-DNS-NAME>/demo
```

Expected result: `HTTP/1.1 200 OK` and a JSON body from the Flask application. The message and version depend on the code currently deployed.

### Test locally through port-forwarding

To access the ClusterIP Service from your workstation:

```bash
kubectl port-forward service/demo-microservice 8080:8080 -n demo
```

Then open `http://localhost:8080/demo` or run:

```bash
curl http://localhost:8080/demo
```

Keep the port-forward command running while testing. This is a local debugging path and does not replace the ALB/Ingress path.

## Screenshots

The screenshots below document local access, request routing, ALB responses, and a successful Jenkins deployment. They are stored in the [`screenshots/`](screenshots/) directory.

### 1. Local testing through port-forward

![Local port-forward test](screenshots/01-local-port-forward.png)

### 2. Request-flow architecture

![Architecture request flow](screenshots/02-architecture-flow.png)

### 3. Ingress and HTTP 200 verification

![Ingress and curl verification](screenshots/03-ingress-and-curl.png)

### 4. ALB response before the application code update

![ALB response version v1](screenshots/04-alb-browser-v1.png)

### 5. ALB response after the application code update

![ALB response version v2](screenshots/05-alb-browser-v2.png)

This screenshot demonstrates a visible application change: the response version changed from `v1` to `v2` after updating the code and deploying the new image.

### 6. Jenkins pipeline success

![Jenkins pipeline completed successfully](screenshots/06-jenkins-pipeline-success.png)

The Jenkins console output shows a successful Helm rollout, a running application Pod, and the image tag deployed by the pipeline.

## What has been completed

- Built the Flask microservice Docker image and pushed it to Amazon ECR.
- Created an Amazon EKS cluster and deployed the application using Helm.
- Installed the AWS Load Balancer Controller.
- Created a Kubernetes Ingress that provisioned an internet-facing ALB.
- Routed external HTTP requests for `/demo` to the application Service and Pod.
- Verified the application through the ALB and received HTTP `200 OK`.
- Updated the application response from `v1` to `v2` and verified the change through the ALB.
- Ran the Jenkins pipeline successfully, including image publication, Helm deployment, and rollout verification.

## Notes and security considerations

- The example ALB endpoint uses HTTP. For production, configure HTTPS with an appropriate TLS certificate and redirect HTTP to HTTPS.
- Restrict access to the Jenkins UI and SSH to trusted IP ranges; avoid exposing administrative interfaces to the entire internet.
- Use least-privilege IAM permissions for Jenkins and Kubernetes access.
- Do not commit credentials, kubeconfig secrets, Terraform state files, or generated provider binaries to Git.
- A successful single-replica deployment proves the delivery path works; production availability requires capacity planning, multiple replicas, suitable node resources, and deliberate distribution across failure domains.
