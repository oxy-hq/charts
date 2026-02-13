# Oxy helm charts

This repository contains Helm charts for oxy-hq. Use this root README as a concise index; chart-level usage and installation details live in each chart's README.

## Charts

### [Oxy App](charts/oxy-app/README.md)

A production-ready Helm chart for deploying the Oxy application on Kubernetes. This chart provides a full-featured deployment with support for external databases (PostgreSQL, ClickHouse), persistence, ingress, observability via OpenTelemetry, and various authentication options. Ideal for scalable, cloud-native deployments with fine-grained control over resources and configuration.

**Key features:**

- PostgreSQL and ClickHouse database support
- Git sync capabilities for configuration management
- HTTP authentication and SSH secrets
- OpenTelemetry collector integration
- Ingress and service configuration
- Pod disruption budgets for high availability

### [Oxy Start](charts/oxy-start/README.md)

A simplified, self-contained Helm chart that uses Docker-in-Docker (DinD) to run Oxy with `oxy start`, managing all services internally within a single pod. Perfect for development environments, demos, or scenarios where you need a quick, all-in-one deployment without external dependencies.

**Key features:**

- Docker-in-Docker deployment model
- Self-contained with no external database requirements
- Simplified configuration
- Ideal for development and testing

## Installation

The `oxy-app` chart is available as an OCI-compatible package at `ghcr.io/oxy-hq/helm-charts` and also from the classic Helm repository at `https://oxy-hq.github.io/charts/`.

Please refer to individual chart directories for specific instructions and configurations.
