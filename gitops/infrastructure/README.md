# Phase 3 — Zero-Trust AI Gateway

This folder will host the infrastructure layer for the security and
model-access components described in phase 3 of the thesis project.

## Planned components

- Vault for secret storage and Kubernetes auth
- LiteLLM as the OpenAI-compatible gateway
- Ollama as the local model runtime on the host

## Current status

The gateway layer is scaffolded. The next step is to add Helm values,
Kubernetes manifests, and secret injection wiring.
