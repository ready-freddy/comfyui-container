name: build-and-push

on:
  push:
    branches: [ main ]
    paths:
      - 'Dockerfile'
      - '.github/workflows/build.yml'
      - 'scripts/**'
      - '.dockerignore'
  workflow_dispatch: {}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    env:
      REGISTRY: ghcr.io

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Debug tree
        run: |
          echo "::group::Repository tree"
          ls -la
          echo
          echo "scripts/:"
          ls -la scripts || true
          echo "::endgroup::"

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Compute image ref (lowercase)
        id: vars
        run: |
          OWNER_LC="$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')"
          REPO_LC="$(echo "${GITHUB_REPOSITORY#*/}" | tr '[:upper:]' '[:lower:]')"
          echo "ref=${OWNER_LC}/${REPO_LC}:cu128-py312-stable" >> "$GITHUB_OUTPUT"

      - name: Build & Push (cu128 only)
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          provenance: false
          sbom: false
          tags: |
            ${{ env.REGISTRY }}/${{ steps.vars.outputs.ref }}
          build-args: |
            CUDA_TAG=12.8.0
