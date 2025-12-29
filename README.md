# Application

[Healarr](https://github.com/binhex/arch-healarr)

## Description

Healarr monitors Docker containers for unhealthy status and automatically performs configurable actions (restart, stop, pause, unpause, kill) with retry logic to prevent false positives. It supports filtering containers by label, environment variable, or name, and includes comprehensive logging.

**Key Features:**

- Monitors Docker containers with health checks for unhealthy status
- Configurable retry logic to verify unhealthy state before taking action
- Multiple filtering options: by label, environment variable, or container name (OR logic)
- Configurable actions: restart, stop, pause, unpause, kill
- Structured logging with configurable log levels
- Graceful shutdown handling

## Build notes

Arch Linux base with Docker CLI.

## Usage

```bash
docker run -d \
    --name=<container name> \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v <path for config files>:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e MONITOR_INTERVAL=<seconds between health checks> \
    -e RETRY_COUNT=<number of retry checks> \
    -e RETRY_DELAY=<seconds between retries> \
    -e ACTION=<restart|stop|pause|unpause|kill> \
    -e CONTAINER_LABEL=<label to filter> \
    -e CONTAINER_ENV_VAR=<env var to filter> \
    -e CONTAINER_NAME=<comma separated names> \
    -e LOG_LEVEL=<0|1|2|3> \
    -e ENABLE_HEALTHCHECK=<yes|no> \
    -e HEALTHCHECK_COMMAND=<command> \
    -e HEALTHCHECK_ACTION=<action> \
    -e HEALTHCHECK_HOSTNAME=<hostname> \
    -e UMASK=<umask for created files> \
    -e PUID=<uid for user> \
    -e PGID=<gid for user> \
    ghcr.io/binhex/arch-healarr
```

Please replace all user variables in the above command defined by <> with the
correct values.

**Required Mount:**

- `/var/run/docker.sock:/var/run/docker.sock` - Docker socket access (required for container management)

## Environment Variables

| Variable | Values | Default | Description |
| -------- | ------ | ------- | ----------- |
| `MONITOR_INTERVAL` | integer | `60` | Time in seconds between checking for unhealthy containers |
| `RETRY_COUNT` | integer | `3` | Number of times to verify unhealthy status before taking action |
| `RETRY_DELAY` | integer | `10` | Time in seconds to wait between retry health checks |
| `ACTION` | restart\|stop\|pause\|unpause\|kill | `restart` | Docker action to execute on unhealthy containers |
| `CONTAINER_LABEL` | string | _(empty)_ | Filter containers by label (e.g. `com.example.monitor=true`) |
| `CONTAINER_ENV_VAR` | string | _(empty)_ | Filter containers by environment variable (e.g. `MONITOR_ENABLED=true`) |
| `CONTAINER_NAME` | string | _(empty)_ | Filter containers by name, comma-separated (e.g. `sonarr,radarr,plex`) |
| `LOG_LEVEL` | 0\|1\|2\|3 | `1` | Logging level: `0`=DEBUG, `1`=INFO, `2`=WARN, `3`=ERROR |
| `ENABLE_HEALTHCHECK` | yes\|no | `no` | Enable or disable healthchecks for this container |
| `HEALTHCHECK_COMMAND` | string | <DNS/HTTPS and process checks> | Custom healthcheck command |
| `HEALTHCHECK_ACTION` | string | `exit 1` | Action on healthcheck failure, e.g. `exit 1` or `kill 1`) |
| `HEALTHCHECK_HOSTNAME` | string | `google.com` | Hostname for healthcheck DNS/HTTPS tests |
| `PUID` | integer | `99` | User ID for the running container |
| `PGID` | integer | `100` | Group ID for the running container |
| `UMASK` | integer | `000` | UMASK for created files |

**Note:** Filters (`CONTAINER_LABEL`, `CONTAINER_ENV_VAR`, `CONTAINER_NAME`) use OR logic. If no filters are specified, all containers with health checks will be monitored.

## Access application

N/A, daemon only. Check logs for monitoring activity.

## Examples

### Example 1: Monitor all containers, restart unhealthy ones

```bash
docker run -d \
    --name=healarr \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /apps/docker/healarr:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e MONITOR_INTERVAL=60 \
    -e RETRY_COUNT=3 \
    -e RETRY_DELAY=10 \
    -e ACTION=restart \
    -e LOG_LEVEL=1 \
    -e UMASK=000 \
    -e PUID=99 \
    -e PGID=100 \
    ghcr.io/binhex/arch-healarr
```

### Example 2: Monitor specific containers by name

```bash
docker run -d \
    --name=healarr \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /apps/docker/healarr:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e MONITOR_INTERVAL=120 \
    -e RETRY_COUNT=5 \
    -e RETRY_DELAY=15 \
    -e ACTION=restart \
    -e CONTAINER_NAME="sonarr,radarr,plex,jellyfin" \
    -e LOG_LEVEL=1 \
    -e UMASK=000 \
    -e PUID=99 \
    -e PGID=100 \
    ghcr.io/binhex/arch-healarr
```

### Example 3: Monitor containers with specific label

```bash
docker run -d \
    --name=healarr \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /apps/docker/healarr:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e MONITOR_INTERVAL=90 \
    -e RETRY_COUNT=3 \
    -e RETRY_DELAY=10 \
    -e ACTION=restart \
    -e CONTAINER_LABEL="healarr.monitor=true" \
    -e LOG_LEVEL=1 \
    -e UMASK=000 \
    -e PUID=99 \
    -e PGID=100 \
    ghcr.io/binhex/arch-healarr
```

### Example 4: Monitor by environment variable, stop unhealthy containers

```bash
docker run -d \
    --name=healarr \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /apps/docker/healarr:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e MONITOR_INTERVAL=60 \
    -e RETRY_COUNT=2 \
    -e RETRY_DELAY=20 \
    -e ACTION=stop \
    -e CONTAINER_ENV_VAR="AUTO_HEAL=true" \
    -e LOG_LEVEL=2 \
    -e UMASK=000 \
    -e PUID=99 \
    -e PGID=100 \
    ghcr.io/binhex/arch-healarr
```

## Notes

User ID (PUID) and Group ID (PGID) can be found by issuing the following command
for the user you want to run the container as:-

```bash
id <username>
```

___
If you appreciate my work, then please consider buying me a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Documentation](https://github.com/binhex/documentation) | [Support forum](http://forums.unraid.net/index.php?topic=TBD)
