# Contributing to the Project

First off, thank you for considering contributing to this repository! We appreciate your time and effort.

## Reporting Bugs

Bugs are tracked and managed via GitHub Issues. We have set up specific **Issue Templates** to make this process as smooth as possible.
When reporting a bug, please select the appropriate template and fill out all the requested information. The templates are designed to extract all the necessary details we need to reproduce and fix the issue.

## Git Submodules

Please note that this repository uses **Git submodules** to manage the wiki files located in the `wiki` directory.
Because of the submodule structure, a standard clone command will leave the `wiki` directory empty. To clone the repository and initialize the submodules at the same time, please use the `--recursive` flag:

`$ git clone --recursive https://github.com/sunweaver/nextcloud-high-performance-backend-setup.git`

If you have already cloned the repository without the recursive flag, you can fetch and initialize the submodule by running the following command in the project root:

`$ git submodule update --init --recursive`
# Contributing to the Project

First off, thank you for considering contributing to this repository! We appreciate your time and effort.

## Local Development Setup

To set up a local development environment, you will need:
* One or more test Nextcloud instances.
* A disposable VPS instance for the Nextcloud High-Performance-Backend.

**Best Practice:** We highly recommend working with server snapshots for the VPS. Prepare a fresh system, take a snapshot, and simply roll back to this snapshot whenever you need to reset the system for a clean run.

### Setup Steps

1. **Clone the repository** (make sure to include submodules as described above).
2. **Set up remotes** (e.g., pointing to your fork).
3. **Configure settings:** Fill out the `settings.sh` file with your specific variables.
4. **Install dependencies:** Install the required `apt` packages on your VPS. Here is a recommended personal pre-selection of helpful packages:

   `$ sudo apt install devscripts dnsutils git git-extras build-essential nano mc vim sudo ipcalc ipv6calc iproute2 avahi-utils rsync etckeeper nmap`

5. **Create a snapshot** of your VPS *before* running the setup script!
6. **Run the setup:**

   ./setup-nextcloud-hpb.sh settings.sh


## General Pull Request Process

1. Fork the repository and create your feature branch from the `main` branch.
2. Ensure you have initialized submodules so you are testing against the correct environment.
3. Follow the Local Development Setup to test your changes.
4. Push to your fork and open a Pull Request.
5. Provide a clear description of your changes.

---
Thank you for helping us improve!
