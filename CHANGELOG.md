# PostgreSQL Docker Upgrade Script

This script facilitates the upgrade process of a PostgreSQL instance running in a Docker container. It can perform backups, restores, and complete PostgreSQL upgrades between specified versions.

## Features

- **Backup Creation**: Safely backup your current PostgreSQL database.
- **Data Restoration**: Restore your database from a backup.
- **Version Upgrades**: Upgrade PostgreSQL to a new version via Docker.
- **Log Tracking**: Track all operations and errors using a detailed log file.
- **Progress Feedback**: Receive feedback during long operations with progress spinners.
- **Color-Coded Logs**: Easily distinguish between info, warnings, and errors.

## Prerequisites

- Docker and Docker Compose installed on your machine.
- A running PostgreSQL container managed with Docker Compose.
- Sufficient permissions to execute Docker commands and interact with local files.

## Usage

```bash
./script.sh [OPTIONS] <from-version> <to-version>
```

### Options

- `--backup-only <version>`: Create a backup of the specified PostgreSQL version without performing an upgrade.
- `--restore-only <version>`: Restore your database from an existing backup of the specified version without performing an upgrade.
- `--dry-run <from-version> <to-version>`: Simulate a PostgreSQL upgrade without making any actual changes.
- `--help`: Display the help message.

### Example Commands

- Upgrade from PostgreSQL version 13 to 14:
  ```bash
  ./script.sh 13 14
  ```

- Only create a backup of PostgreSQL version 13:
  ```bash
  ./script.sh --backup-only 13
  ```

- Restore database from an existing backup of version 13:
  ```bash
  ./script.sh --restore-only 13
  ```

- Simulate the upgrade from version 13 to 14 without performing any actions:
  ```bash
  ./script.sh --dry-run 13 14
  ```

## File Locations

- **Backups**: Stored in `./postgres-upgrade/backups`
- **Logs**: Located at `./postgres-upgrade/upgrade.log`

## Logging

The script includes a logging function, which outputs messages in different colors to the console and writes them to a log file. The log contains timestamps, log levels (INFO, WARNING, ERROR, PROGRESS), and messages.

## Error Handling

- The script stops execution (`set -e`) on command failures, undefined variables, or pipe failures.
- A trap function is used to catch errors and report the line number where an error occurs.

## Notes

- Ensure that you have sufficient disk space for backups.
- The script assumes a Docker Compose setup managing the PostgreSQL container.
- A `docker-compose.yml` file is expected in the script's directory for configuring PostgreSQL containers.

## License

This script is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.