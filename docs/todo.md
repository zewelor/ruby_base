# Todo List

- [x] Update `.github/workflows/docker_checks.yml` triggers to run on `push` (restricted to `main` branch), `pull_request`, and keep `workflow_dispatch`.
- [x] Remove `if: github.ref == 'refs/heads/main'` from the `push_production` job to allow it to run on Pull Requests.
- [x] Make registry login conditional on `github.event_name == 'push'`.
- [x] Make `docker/build-push-action` push setting conditional: `push: ${{ github.event_name == 'push' }}`.
- [x] Make deletion of old package versions conditional on `github.event_name == 'push'`.
- [x] Verify workflow file YAML syntax.
- [x] Implement conditional platforms for production build (only build `linux/amd64` on PR, both on `push`).
- [x] Implement conditional `cache-to` (only save cache on `push` to main).
- [x] Fix missing `id: buildx` in the `Set up Docker Buildx` step of the `push_production` job.

## Review Section

The GitHub Actions workflow has been updated to follow the pattern used in the `feedway` repository, with extra performance optimizations and a bugfix implemented:
- **Triggers**: Now triggers on push to the `main` branch, on all pull requests, and via manual dispatch (`workflow_dispatch`).
- **Conditional Pushing**: The `push_production` job now runs on all pull requests to validate the production build. However, the image is only pushed to the container registry, the login step is performed, and old image versions are deleted when the event is a `push` (which corresponds to commits merged/pushed directly to the `main` branch).
- **Optimization 1: Conditional Platforms**: On Pull Requests, the workflow only builds the image for the `linux/amd64` architecture (avoiding slow QEMU emulation for `linux/arm64`). On a merge/push to `main`, it builds for both `linux/amd64` and `linux/arm64`.
- **Optimization 2: Conditional Cache Export**: Cache writing (`cache-to`) is only performed on push to the `main` branch, preventing cache writes from Pull Requests and keeping the primary cache clean.
- **Bugfix: Missing buildx ID**: Added `id: buildx` to the `Set up Docker Buildx` step in the `push_production` job to correct the reference `${{ steps.buildx.outputs.name }}` in the build-push action.
- **Validation**: Verified the YAML structure of the updated workflow file.
