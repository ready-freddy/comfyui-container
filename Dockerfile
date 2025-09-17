name: Build & Push (py312 • cu128)

on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Image tag to push (e.g., cu128-py312-v1 or 2025-09-17a)"
        required: true
        default: "cu128-py312-v1"
      image_name:
        description: "Full image name (registry/owner/name)"
        required: true
        default: "ghcr.io/${{ github.repository_owner }}/comfyui-container"

permissions:
  contents: read
  packages: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    env:
      IMAGE_NAME: ${{ inputs.image_name }}
      IMAGE_TAG:  ${{ inputs.tag }}

    steps:
      - name: Check out branch
        uses: actions/checkout@v4

      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./Dockerfile
          platforms: linux/amd64
          push: true
          tags: ${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}

      - name: Announce
        run: |
          echo "✅ Pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
          echo "Pull with: docker pull ${IMAGE_NAME}:${IMAGE_TAG}"
