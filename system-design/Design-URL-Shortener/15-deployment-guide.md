# Article 16: The Deployment Guide (Infrastructure as Code)

## Stop Clicking Buttons

In Article 1, we manually created a database. In Article 16, that is forbidden.
A Senior Engineer defines infrastructure as code. If the data center burns down, we can rebuild the entire company in 10 minutes with one command: `terraform apply`.

> **Reader path — 5. Deep dives (deployment):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Case studies](14-case-studies.md) → deployment expansion here → [requirements recap](01-introduction-requirements.md). Infrastructure and release steps implement the [working baseline](04-basic-system-design.md) and chosen deep dives; they are not a replacement delivery framework.

---

## 1. The Container Strategy (Docker)

We don't install Node.js on servers. We ship containers.

### `Dockerfile`
```dockerfile
# 1. Build Stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# 2. Run Stage
FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/index.js"]
```
**Why Multi-Stage?** It keeps the final image tiny (50MB) by stripping out build tools.

---

## 2. Infrastructure as Code (Terraform)

We use Terraform to define our AWS resources.

### `main.tf` (Simplified)
```hcl
# 1. The Database
resource "aws_db_instance" "postgres" {
  engine         = "postgres"
  instance_class = "db.t4g.micro"
  allocated_storage = 20
  multi_az       = true  # High Availability
}

# 2. Redis Cluster
resource "aws_elasticache_cluster" "redis" {
  engine           = "redis"
  node_type        = "cache.t4g.micro"
  num_cache_nodes  = 2
}

# 3. The Auto-Scaling Group (API Servers)
resource "aws_autoscaling_group" "api_asg" {
  desired_capacity   = 3
  max_size           = 10
  min_size           = 2
  
  # Auto-Scale based on CPU
  target_group_arns = [aws_lb_target_group.app.arn]
}
```

---

## 3. The CI/CD Pipeline (GitHub Actions)

We never SSH into servers. We push code, and the robots take over.

### `.github/workflows/deploy.yam`
```yaml
name: Deploy to Production
on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      # 1. Run Tests
      - name: Run Unit Tests
        run: npm test
      
      # 2. Build Docker Image
      - name: Build and Push
        run: |
          docker build -t my-shortener .
          docker push my-registry/shortener:latest
          
      # 3. Update Infrastructure
      - name: Terraform Apply
        run: terraform apply -auto-approve
        
      # 4. Rollout Update
      - name: Deploy to ECS
        run: aws ecs update-service --service shortener --force-new-deployment
```

---

## 4. The "Blue/Green" Deploy

**Scenario**: You deployed a bug that causes 500 errors.
**Old Way**: Panic. Rollback takes 10 minutes.
**New Way (Blue/Green)**:
1.  **Blue (Live)**: Running v1.0.
2.  **Green (New)**: We deploy v1.1 to a separate cluster.
3.  **Test**: We run automated smoke tests against Green.
4.  **Switch**: The Load Balancer flips 100% of traffic from Blue to Green.
5.  **Rollback**: If error rate spikes, Flip back to Blue instantly (0 seconds).

---

## Summary
By using Docker, Terraform, and Blue/Green deployments, we turned "Release Day" from a stressful event into a boring, automated routine.
This is the final seal of quality on our URL Shortener. It is scalable, reliable, and deployable.
