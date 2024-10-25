# simple_postgres_upgrade Script

This script facilitates upgrading a PostgreSQL instance running in a Docker container, supporting operations like backups, restores, and version upgrades.

## Key Features

- **Backup Creation**: Safely back up your current PostgreSQL database.
- **Data Restoration**: Restore databases from backups.
- **Version Upgrades**: Seamlessly upgrade PostgreSQL to a specified version using Docker.
- **Log and Error Tracking**: All operations and errors are logged in detail.
- **Progress Feedback**: Progress spinners indicate ongoing operations.
- **Color-Coded Logs**: Info, warnings, and errors are easily distinguishable with colors.

## Prerequisites

- Docker and Docker Compose must be installed.
- Your PostgreSQL container should be managed using Docker Compose.
- Ensure you have permissions to run Docker commands and access local files.

## Updated Usage

```bash
./simple_postgres_upgrade.sh [OPTIONS] <from-version> <to-version>
```

### Options

- `-n, --name NAME`: Specify the container name (mandatory).
- `-d, --data-dir DIR`: Specify the data directory (default: `/var/lib/postgresql/data`).
- `--backup-only`: Create a backup of the specified PostgreSQL version without upgrading.
- `--restore-only`: Restore from an existing backup without upgrading.
- `--dry-run`: Simulate the PostgreSQL upgrade without actual changes.
- `--version`: Display the script version.
- `--help`: Display the help message.

### Updated Example Commands

- Upgrade from PostgreSQL version 13 to 14:
  ```bash
  ./simple_postgres_upgrade.sh -n postgres-db 13 14
  ```

- Create a backup of PostgreSQL version 13:
  ```bash
  ./simple_postgres_upgrade.sh -n postgres-db --backup-only 13
  ```

- Restore from an existing backup of version 13:
  ```bash
  ./simple_postgres_upgrade.sh -n postgres-db --restore-only 13
  ```

- Simulate an upgrade from version 13 to 14:
  ```bash
  ./simple_postgres_upgrade.sh -n postgres-db --dry-run 13 14
  ```

## File Locations

- **Backups**: Stored in `./postgres-upgrade/backups`
- **Logs**: Located at `./postgres-upgrade/upgrade.log`

## Logging and Error Handling

Logs include timestamps and are categorized by level (INFO, WARNING, ERROR, PROGRESS). The script halts on errors due to command failures, undefined variables, or pipe errors, and a trap function reports the error line number.

## Notes

- Ensure sufficient disk space for backups.
- The script assumes Docker Compose manages your PostgreSQL container.
- A `docker-compose.yml` file must be in the script's directory to configure containers.

## License

This script is licensed under the MIT License. Refer to the [LICENSE](LICENSE) file for details.