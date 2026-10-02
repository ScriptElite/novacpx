# NovaCPX auto-deploy

Every NovaCPX server polls its source checkout (`/opt/novacpx-src`, origin = Gitea `admin/novacpx`) once a minute.
When `origin/main` has commits the server has not deployed, `deploy/novacpx-poll-deploy` queues them and runs
`deploy/deploy-runner.sh` (pull, PHP syntax check with rollback, rsync to `/srv/novacpx/public`, DB migrations,
version record, PHP-FPM reload, privileged-helper and poller refresh).

- Ship order for this repo: local -> GitHub -> Gitea; the servers see the Gitea push within a minute.
- No inbound webhook is needed (works on the DO server and on LAN-only VMs).
- Logs: `/var/log/novacpx/autodeploy.log` (poller), `/var/log/novacpx/deploy.log` (runner).
- Installed by `deploy/install-autodeploy.sh` (`/etc/cron.d/novacpx-autodeploy`); `install.sh` and the runner re-run it.
- A checkout with local commits that origin lacks is never deployed over (the poller logs it and stops).
