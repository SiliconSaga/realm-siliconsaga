# SiliconSaga — Local Dev Setup

How to set up a local development environment for the SiliconSaga realm — primarily Nordri's bootstrap and the homelab k3s/k3d cluster it runs on. The generic GDD framework + workspace CLI tooling lives in upstream `yggdrasil` and works on any platform with `bash` + `git`; everything below is the realm-specific *additional* setup.

## Windows Setup

We recommend using **Chocolatey** and **pyenv-win** to manage tools and Python versions. This approach avoids cluttering the system registry and provides a "Unix-like" consistency.

### Install Package Manager (Chocolatey)

Run the following in an **Administrator** PowerShell to install Chocolatey:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### Install Core Tools

Once Chocolatey is installed, use it to install Git and the Python version manager:

```powershell
choco install git pyenv-win -y
```

> **Note**: You may need to restart your terminal after this step for the `pyenv` and `git` commands to be recognized.

### Configure Python (via pyenv)

We use `pyenv` to ensure all developers use the same Python version (Target: **3.11.x**).

#### Install Python

```powershell
# Update pyenv first to ensure latest versions are available
pyenv update

# Install the target version
pyenv install 3.11.11

# Set it as global (or local to this repo)
pyenv global 3.11.11
```

### Verify Installation

```powershell
python --version
# Should output Python 3.11.11
```

### Shell Environment 

This is particularly crucial for Nordri.

Many automation scripts (e.g., `bootstrap.sh`) are written in **Bash**. PowerShell and CMD cannot execute these scripts directly.

*   **Requirement**: You **MUST** use a Bash-compatible shell to run bootstrap and maintenance scripts.
*   **Recommendation**: Use **Git Bash** (installed automatically with Git).
*   **How to use**: 
    * Right-click in your project folder and select "Open Git Bash here"
    * Start a regular `cmd` first then `cd "C:\Program Files\Git\bin"` and run `bash` from there.
    * Do the same with PS but make sure to run it as `./bash.exe`
    * **Navigation Tip**: Git Bash uses POSIX paths. To access your files on the `D:` drive, use `/d/`.
        *   Example: `cd /d/Dev/GitWS/nordri`
    * **MSYS Path Mangling**: Git Bash (MSYS2) auto-converts paths starting with `/` to Windows paths (e.g., `/garage` becomes `C:/Program Files/Git/garage`). This breaks `kubectl exec` commands that pass absolute paths to containers. The bootstrap script handles this with `export MSYS_NO_PATHCONV=1`. If running kubectl commands manually, either prefix with `MSYS_NO_PATHCONV=1` or use PowerShell instead.

### Kubernetes Prerequisites

For Nordri development on Windows, we suggest **Rancher Desktop**

*   **K3s Binary**: Note that when using Rancher Desktop, the `k3s` binary exists *inside* the virtual machine. It is **normal** that `k3s --version` fails in your Windows terminal. You only need `kubectl` (which Rancher installs) to interact with the cluster.
*   **Disable System Traefik**: You **MUST** disable the default Traefik in Rancher Desktop to avoid conflicts with our custom Gateway API implementation.
    *   *Settings -> Kubernetes -> Uncheck "Traefik"*.
    *   (This will restart the Kubernetes cluster).

    > **Note**: The bootstrap script tries to automatically install `open-iscsi` (required for Longhorn) if running on Rancher Desktop. On other distros (standard K3s, generic Linux), ensure `open-iscsi` (or `iscsi-initiator-utils`) is installed on the underlying nodes.

If you need _additional_ k3s clusters beyond the one provided by Rancher Desktop, you could install the full `k3d` environment that works via Docker and manage multiple clusters that way. This could also be a fine approach on Mac or Linux.

### Crossplane CLI (offline composition rendering)

The `crossplane` CLI lets you render a Composition offline — no cluster needed — which catches go-templating errors and verifies env-aware values (storageClass, domains) before anything deploys. Compositions in this stack are exercised this way; nidavellir ships ready-made fixtures under `tests/render/` (heimdall's composition renders the same way but has no committed fixtures yet).

**Install — build from source (recommended):** the published release checksums are currently unreliable (observed 2026-06-10: the `.sha256` files in the release bucket did not match the actual v2.3.1/v2.3.2 binaries, and the Windows exes are not Authenticode-signed). Until upstream fixes that, build the CLI from source — Go makes this a one-liner and the provenance is the source repo itself. Prerequisite: a Go toolchain — check with `go version`; any Go ≥ 1.21 works because it auto-fetches the toolchain crossplane's `go.mod` actually requires (`GOTOOLCHAIN=auto` is the default). Missing or ancient: `choco install golang` (Windows), `brew install go` (macOS), https://go.dev/doc/install (Linux).

```bash
go install github.com/crossplane/crossplane/cmd/crank@v2.3.2
```

`go install` drops the binary in `$GOBIN` (default `~/go/bin` — `C:\Users\<you>\go\bin` on Windows). It builds as `crank`, the CLI's internal name, so rename a copy to `crossplane` somewhere on your PATH:

```bash
# Linux / macOS (~/go/bin is on PATH if your profile exports it)
cp ~/go/bin/crank ~/go/bin/crossplane

# Windows (Git Bash) — or copy to any tools dir already on PATH
cp ~/go/bin/crank.exe ~/go/bin/crossplane.exe
```

If the target directory isn't on PATH yet: add `export PATH="$HOME/go/bin:$PATH"` to your shell profile (Linux/macOS/Git Bash), or on Windows add it under *Settings → System → About → Advanced system settings → Environment Variables*. Verify with `crossplane version --client`.

**Install — direct download (fallback):** binaries per OS/arch at https://cli.crossplane.io/stable/current/bin (e.g. `windows_amd64/crossplane.exe`); place on PATH (e.g. `D:\Dev\MiscTools`). Treat this as a last resort while the checksum mismatch stands — do not run a downloaded binary whose published `.sha256` doesn't verify unless you've made a deliberate, informed exception (HTTPS + official domain narrows but does not eliminate the risk). macOS can use `brew install crossplane` instead (Homebrew builds carry their own checksums).

**Config:** none. `crossplane render` runs the pipeline functions as local Docker containers, so Docker (Rancher Desktop / Docker Desktop) must be running. First render pulls the function images.

**Usage** — render the OpenBao composition offline. Prerequisite: nidavellir cloned (`ws clone nidavellir`); run from its repo root and confirm the fixtures are present (`ls tests/render/`):

```bash
crossplane render tests/render/openbao-xr.yaml openbao/composition.yaml \
  tests/render/functions.yaml --extra-resources tests/render/cluster-identity-homelab.yaml
```

**Expected output:** three YAML docs and no template errors — the `XOpenBao` XR, a Helm `Release` whose values carry the env-aware fields (`storageClass: local-path` for the homelab fixture), and an `Object` wrapping an HTTPRoute with hostname `openbao.homelab.local`. Wrong/missing storageClass or hostname means the EnvironmentConfig didn't reach the template — that's the failure mode this check exists to catch.

Notes:

- `render` takes an **XR**, not a claim (`tests/render/openbao-xr.yaml` is the bare-XR fixture).
- `function-environment-configs` gets its EnvironmentConfig via `--extra-resources` — swap in `tests/render/cluster-identity-gke.yaml` to check the other environment (expect `storageClass: standard-rwo` and hostname `openbao.cmdbee.org`).
- Pin function versions in `functions.yaml` to what the cluster runs (`kubectl get functions.pkg.crossplane.io`).

### WSL2 inotify Limits

Rancher Desktop runs k3s inside a WSL2 VM. The default Linux `inotify` limits are too low
for clusters running multiple Kubernetes operators (each operator watches many resources).
Symptoms include operators crash-looping with `too many open files` errors — the Percona
XtraDB (MySQL) operator is typically the first to hit this.

**Check current values:**

```powershell
wsl -d rancher-desktop sudo sysctl fs.inotify.max_user_watches
wsl -d rancher-desktop sudo sysctl fs.inotify.max_user_instances
```

**Required minimums** (defaults are 524288 watches / 128 instances):

| Setting | Default | Required |
|---------|---------|----------|
| `fs.inotify.max_user_watches` | 524288 | 524288 (usually fine) |
| `fs.inotify.max_user_instances` | 128 | 512 |

**Apply (non-persistent — resets on WSL restart):**

```powershell
wsl -d rancher-desktop sudo sysctl -w fs.inotify.max_user_instances=512
```

**Apply (persistent across restarts):**

```powershell
wsl -d rancher-desktop sudo sh -c 'echo "fs.inotify.max_user_instances=512" >> /etc/sysctl.conf'
```

> **Note**: After a Rancher Desktop or WSL restart, verify the values are still set.
> If the persistent method doesn't survive restarts (some WSL distros reset `/etc/sysctl.conf`),
> add the `sysctl -w` command to your post-reset checklist.

### Resetting the Environment

If you need to wipe the cluster clean (e.g., to clear out old deployments before a fresh bootstrap), use the Rancher Desktop CLI (`rdctl`) or the GUI.

*   **GUI**: *File -> Preferences -> Troubleshooting -> Reset Kubernetes*.
*   **CLI**:

    ```powershell
    # Resets just the Kubernetes workloads (keeping images/settings)
    rdctl reset --k8s

    # Factory reset (wipes everything, including images)
    # rdctl reset --factory
    ```

### PowerShell Quirks & Troubleshooting

PowerShell's default security settings can sometimes block `pyenv` scripts.

*   **Execution Policy Error**: If you see "cannot be loaded because running scripts is disabled", allow scripts for the current process:

    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
    ```

*   **Outdated Version List**: If `pyenv install --list` shows only old versions (e.g., stopping at 3.11.0a), your local pyenv definitions are stale. Update them manually:

    ```powershell
    # Navigate to the pyenv-win directory
    cd $env:USERPROFILE\.pyenv\pyenv-win

    # Ensure you are on the master branch (fix detached head state)
    git checkout master

    # Pull latest changes
    git pull
    ```

*   **"Python was not found" / Microsoft Store opens**:
    If running `python` opens the Microsoft Store or says "Python was not found" despite successful installation:
    1.  Go to Windows Settings > Apps > Advanced app settings > **App execution aliases**.
    2.  Toggle **OFF** the entries for `python.exe` and `python3.exe`.

---

## macOS Setup

We recommend using **Homebrew** to manage tools and **pyenv** for Python versions.

### Install Package Manager (Homebrew)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install Core Tools

```bash
brew install git pyenv k3d kubectl helm kuttl crossplane
```

(`crossplane` is the CLI for offline composition rendering — see the Crossplane CLI section under Windows Setup for what it's for and how to use it; the Homebrew formula sidesteps the upstream checksum caveat described there.)

### Configure Python (via pyenv)

Same as the Windows section — target **3.11.x**:

```bash
pyenv install 3.11.11
pyenv global 3.11.11
```

Add to your `~/.zshrc` (macOS default shell is zsh):

```bash
eval "$(pyenv init -)"
```

### Kubernetes Setup

We use **k3d** (k3s-in-Docker) for local development clusters. Docker Desktop (or an alternative like OrbStack) must be installed.

**Create a cluster** (disable built-in Traefik since Nordri installs its own):

```bash
k3d cluster create refr-k8s \
  --port "8080:80@loadbalancer" --port "8443:443@loadbalancer" \
  --agents 2 --k3s-arg "--disable=traefik@server:*"
```

**Run the bootstrap**:

```bash
cd /path/to/nordri
./bootstrap.sh homelab
```

> **Note on Longhorn**: Longhorn requires `open-iscsi` on cluster nodes. k3d nodes are Docker containers that lack `iscsid`, so Longhorn will not function. The cluster uses the built-in `local-path` storage provisioner instead, which is sufficient for development. For a full-stack environment (including Longhorn), consider using **Rancher Desktop** on macOS, which provides a real VM where `open-iscsi` can be installed.

### Shell Notes

*   macOS uses **zsh** by default. Bash scripts (e.g., `bootstrap.sh`) work fine from Terminal.
*   The scripts handle `sed -i` macOS incompatibility automatically (no user action needed).

### Resetting the Environment

```bash
# Delete the k3d cluster
k3d cluster delete refr-k8s

# Recreate from scratch
k3d cluster create refr-k8s \
  --port "8080:80@loadbalancer" --port "8443:443@loadbalancer" \
  --agents 2 --k3s-arg "--disable=traefik@server:*"
./bootstrap.sh homelab
```

## Linux Setup (Coming Soon)
