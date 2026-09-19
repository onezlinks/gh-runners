# gh-runners

Self-hosted GitHub Actions runners in Docker — one command to run, built for
single repos, org-wide pools, and multi-project setups.

- **Fresh tokens, always** — registration/remove tokens are minted on demand via
  a PAT, so `restart: always` actually works (no more 1-hour `REG_TOKEN` expiry
  or ghost runners left behind on GitHub)
- **Replica-safe** — every container registers a unique runner name
  (`<name>-<hostname>`), so scaling up just works
- **Multi-arch image** — one Dockerfile covers `linux/amd64` and `linux/arm64`
  (runs on Mac via Docker Desktop too)
- **Repo or org scope** — point `REPO` at `owner/repo` or just `owner` for an
  organization runner shared across repos

## Quickstart

```bash
cp .env.example .env   # set REPO and GH_PAT
docker compose up -d
```

That's it — two runner replicas register themselves and start listening for jobs.

## Running for multiple repos

### Option A — organization runner (easiest)

If your repos live in one org, set `REPO=<org>` in `.env`. A single pool serves
every repo allowed by its runner group (org settings → Actions → Runner groups).
Adding a repo later requires **zero config changes** — just allow it in the group.

### Option B — one service per project

Create an env file per project and add a service block in `docker-compose.yml`:

```yaml
# env/retro-snap.env → REPO=owner/retro-snap, GH_PAT=...
services:
  retro-snap:
    <<: *runner
    env_file: env/retro-snap.env
    deploy:
      replicas: 1
```

Containers are named `gh-runners-<service>-<n>`. Docker Compose automatically
picks up `docker-compose.override.yml` too — a handy gitignored spot for local
services.

## Running Docker jobs (DooD gotcha)

Jobs drive the **host** Docker daemon through the mounted socket, so every
bind-mount path in a job (`docker run -v "$PWD/..."`, compose volumes, …) is
resolved against the **host** filesystem. A checkout path that only exists
inside the runner container silently becomes an empty directory on the host —
the classic `IO error: Is a directory` symptom.

The fix is to give each runner its own work directory bind-mounted at an
**identical path on host and container**:

```yaml
services:
  runner-1:
    <<: *runner
    environment:
      WORK_DIR: /opt/gh-runners/work-1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/gh-runners/work-1:/opt/gh-runners/work-1   # same path both sides
```

Create the dirs first so the `docker` user (uid 1001) can write them:

```bash
install -d -o 1001 -g "$(stat -c %g /var/run/docker.sock)" /opt/gh-runners/work-1
```

Each runner needs its **own** work dir (two jobs for the same repo would
otherwise share a checkout), which is why this setup uses one service per
runner instead of `replicas:`.

## Configuration

| Variable              | Required | Description |
|-----------------------|----------|-------------|
| `REPO`                | yes      | `owner/repo` for a repo runner, `owner` for an org runner |
| `GH_PAT`              | yes*     | PAT used to mint tokens. `repo` scope (repo runner) or `admin:org` (org runner) |
| `REG_TOKEN`           | yes*     | Alternative to `GH_PAT`. Expires in ~1h — not for `restart: always` |
| `NAME`                | no       | Base runner name (default: repo/org name). Hostname appended automatically |
| `LABELS`              | no       | Extra comma-separated labels |
| `RUNNER_GROUP`        | no       | Runner group (org/enterprise only) |
| `WORK_DIR`            | no       | Working directory inside the container |
| `EPHEMERAL`           | no       | `true` → runner deregisters after one job |
| `DISABLE_AUTO_UPDATE` | no       | `true` → skip runner self-update |

\* one of `GH_PAT` / `REG_TOKEN` is required.

## Using a published image

The repo ships a workflow (`.github/workflows/publish.yml`) that pushes a
multi-arch image to GHCR on every `v*` tag. To use it instead of building,
swap `build: .` for `image: ghcr.io/<owner>/<repo>:latest` in `docker-compose.yml`.

## Security notes

- Runners mount `/var/run/docker.sock` — jobs can control the host's Docker
  daemon. Only run trusted workflows; never expose runners to public repos that
  accept outside pull requests.
- `.env` and `env/*.env` are gitignored. Never commit tokens or PATs.
- Prefer `EPHEMERAL=true` for untrusted-ish workloads: each job gets a fresh,
  clean runner that deregisters itself afterwards.

## License

[MIT](LICENSE)
