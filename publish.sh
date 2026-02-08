#!/bin/bash
set -euo pipefail

IMAGE="amirsafiallah/ikesocks"
VERSION="${1:-latest}"

echo "==> Building ${IMAGE}:${VERSION} (linux/amd64,linux/arm64)..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t "${IMAGE}:${VERSION}" \
    -t "${IMAGE}:latest" \
    --push \
    .

echo "==> Published:"
echo "    ${IMAGE}:${VERSION}"
echo "    ${IMAGE}:latest"
