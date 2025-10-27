---
name: Bug report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description
A clear and concise description of what the bug is.

## Steps to Reproduce
Steps to reproduce the behavior:
1. Go to '...'
2. Run command '....'
3. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
A clear and concise description of what actually happened.

## Environment
- Debian version: [e.g. Debian 12]
- Nextcloud version: [e.g. 28.0.1]
- Script version: [output of `cat VERSION`]
- Architecture: [e.g. x86_64, aarch64]

## Log Files
**Important:** The setup script creates log files with the date of execution. Please attach relevant log files, but **make sure to censor sensitive information** (passwords, domains, IP addresses, etc.) before uploading.

### Setup Log
Location: `setup-nextcloud-hpb-YYYY-MM-DDTHH:MM:SSZ.log` (in the script execution directory)

<details>
<summary>Setup Log (click to expand)</summary>

```
Paste censored log content here
```

</details>

### System Logs
If applicable, please also provide the following logs (remember to censor sensitive data):

<details>
<summary>Nginx Error Logs</summary>

```bash
# Command used:
$ sudo cat /var/log/nginx/*_error.log

# Output (censored):
Paste censored output here
```

</details>

<details>
<summary>Service Status</summary>

```bash
# Commands used:
$ systemctl status nginx
$ systemctl status nats-server
$ systemctl status nextcloud-spreed-signaling
$ systemctl status janus
$ systemctl status coturn
$ systemctl status collabora

# Output:
Paste output here
```

</details>

## Screenshots
If applicable, add screenshots to help explain your problem.

## Additional Context
Add any other context about the problem here.

## Checklist
- [ ] I have checked existing issues for duplicates
- [ ] I have censored all sensitive information from logs and screenshots
- [ ] I have included the setup log file
- [ ] I have included relevant system logs
- [ ] I have added screenshots where applicable
