# Grandstream GWN Manager Container

Container image and Kubernetes deployment for [Grandstream GWN Manager](https://www.grandstream.com/), built from the official Linux installer.

This repository provides:

- A container build for GWN Manager.
- A Kubernetes StatefulSet with persistent application data and configuration.
- Automated image builds and publication to GitHub Container Registry (GHCR).

## Use

The container image is published at `ghcr.io/s-b-v/grandstream-gwn-manager`.

For Kubernetes installation and access, see [README-k8s.md](README-k8s.md).

For using the automated image release process, see [README-ci.md](README-ci.md).

The application is supplied by Grandstream; its own license and terms apply.
