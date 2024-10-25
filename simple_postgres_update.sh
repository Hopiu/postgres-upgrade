#!/bin/bash

# Exit on error, undefined variables, and propagate pipe failures
set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# Configuration
SCRIPT_VERSION="0.0.1"
DATA_DIRECTORY="/var/lib/postgresql/data"  # Default PostgreSQL data directory
BACKUP_DIR="./postgres-upgrade/backups"
LOG_FILE="./postgres-upgrade/upgrade.log"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Progress spinner characters
SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Logging function with colors
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            local color=$GREEN
            ;;
        "WARNING")
            local color=$YELLOW
            ;;
        "ERROR")
            local color=$RED
            ;;
        "PROGRESS")
            local color=$BLUE
            ;;
        *)
            local color=$NC
            ;;
    esac

    echo -e "${color}[${timestamp}] ${level}: ${message}${NC}" | tee -a "$LOG_FILE"
}

# Progress spinner function
show_spinner() {
    local pid=$1
    local message=$2
    local i=0
    local spin_len=${#SPINNER}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i + 1) % spin_len ))
        printf "\r${BLUE}[${timestamp}] PROGRESS: %s %s${NC}" "$message" "${SPINNER:$i:1}"
        sleep 0.1
    done
    printf "\r"
}

# Modify the check_container_status function to include container logs on failure
check_container_status() {
    local wait_time=${1:-5}
    local retries=$((wait_time + 1))

    while [ $retries -gt 0 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
                log "INFO" "Container ${CONTAINER_NAME} is running and ready"
                return 0
            fi

            # Add container logs check if pg_isready fails
            local container_logs=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -n 5)
            log "INFO" "Container logs: $container_logs"
        fi

        if [ $wait_time -gt 0 ]; then
            retries=$((retries - 1))
            if [ $retries -gt 0 ]; then
                printf "\r${BLUE}Waiting for container to be ready... (%d seconds remaining)${NC}" $retries
                sleep 1
            fi
        fi
    done

    # Show container logs on timeout
    log "ERROR" "Container logs on failure:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -n 20 | while read -r line; do
        log "ERROR" "$line"
    done

    return 1
}

# Function to perform database dump
dump_database() {
    local version=$1
    local dump_file="${BACKUP_DIR}/dump_v${version}_${BACKUP_TIMESTAMP}.sql"

    # Check if container is running before proceeding
    if ! check_container_status; then
        log "ERROR" "Cannot perform database dump - container is not running"
        return 1
    fi

    log "INFO" "Creating backup of PostgreSQL $version database..."
    mkdir -p "$BACKUP_DIR"

    # Start dump with progress indication
    (docker exec "$CONTAINER_NAME" pg_dumpall -U postgres > "$dump_file") &
    show_spinner $! "Creating database dump..."

    if [ -f "$dump_file" ] && [ -s "$dump_file" ]; then
        log "INFO" "Database dump created successfully at $dump_file"
        # Calculate dump size
        local dump_size=$(du -h "$dump_file" | cut -f1)
        log "INFO" "Dump size: $dump_size"
        return 0
    else
        log "ERROR" "Failed to create database dump"
        return 1
    fi
}

# Function to verify backup
verify_backup() {
    local version=$1
    local dump_file="${BACKUP_DIR}/dump_v${version}_${BACKUP_TIMESTAMP}.sql"

    if [ -z "$dump_file" ]; then
        log "ERROR" "No backup file found for version $version"
        return 1
    fi

    log "INFO" "Verifying backup integrity..."

    if [ ! -f "$dump_file" ]; then
        log "ERROR" "Backup file not found: $dump_file"
        return 1
    fi

    # Check if dump file contains expected PostgreSQL dump content
    if grep -q "PostgreSQL database dump complete" "$dump_file"; then
        log "INFO" "Backup verification successful"
        return 0
    else
        log "ERROR" "Backup verification failed"
        return 1
    fi
}

# Function to update docker-compose.yml
update_version() {
    local new_version=$1
    log "INFO" "Updating PostgreSQL version to $new_version..."

    # Backup original docker-compose file
    cp docker-compose.yml docker-compose.yml.bak

    # Update PostgreSQL version
    sed -i.bak "s/postgres:[0-9][0-9]*/postgres:$new_version/" docker-compose.yml
}

# Function to restore database
restore_database() {
    local version=$1
    local dump_file="${BACKUP_DIR}/dump_v${version}_${BACKUP_TIMESTAMP}.sql"

    if [ -z "$dump_file" ]; then
        log "ERROR" "No backup file found for version $version"
        return 1
    fi

    log "INFO" "Restoring database from $dump_file..."

    # Check if container is running with a 30-second timeout
    if ! check_container_status 30; then
        log "ERROR" "Cannot perform database restore - container failed to start"
        return 1
    fi

    # Start restore with progress indication
    (docker exec -i "$CONTAINER_NAME" psql -U postgres < "$dump_file") &
    show_spinner $! "Restoring database..."

    if [ $? -eq 0 ]; then
        log "INFO" "Database restored successfully"
        return 0
    else
        log "ERROR" "Failed to restore database"
        return 1
    fi
}

# Function to perform dry run
dry_run() {
    local from_version=$1
    local to_version=$2

    log "INFO" "Performing dry run for upgrade from PostgreSQL $from_version to $to_version"
    echo
    echo -e "${YELLOW}The following operations would be performed:${NC}"
    echo "1. Check if container is running"
    echo "2. Create backup of version $from_version database"
    echo "   - Backup location: $BACKUP_DIR/dump_v${from_version}.sql"
    echo "3. Stop PostgreSQL container ($CONTAINER_NAME)"
    echo "4. Remove existing PostgreSQL data"
    echo "5. Update docker-compose.yml to version $to_version"
    echo "6. Start new PostgreSQL container"
    echo "7. Wait for container to be ready"
    echo "8. Restore database from backup"
    echo
    echo -e "${YELLOW}Existing backups:${NC}"
    ls -lh "${BACKUP_DIR}"/*.sql 2>/dev/null || echo "No backups found"
    echo
    log "INFO" "Dry run completed"
}

# Display version information
display_version() {
    echo -e "${GREEN}PostgreSQL Docker Upgrade Script${NC} - Version $SCRIPT_VERSION"
}

# Function to display usage
usage() {
    cat << EOF | sed 's/\x1B\[[0-9;]*[JKmsu]//g' | while IFS= read -r line; do echo -e "$line"; done
${GREEN}PostgreSQL Docker Upgrade Script${NC}

Usage: $0 [OPTIONS] <from-version> <to-version>

Options:
  -n, --name NAME       Container name (mandatory)
  -d, --data-dir DIR    Data directory (default: /var/lib/postgresql/data)
  --backup-only         Create backup without performing upgrade
  --restore-only        Restore from an existing backup without performing upgrade
  --dry-run            Show what would happen without making changes
  --version            Display script version
  --help               Display this help message

Example:
  $0 -n postgres-db 13 14         # Upgrade from PostgreSQL 13 to 14
  $0 -n postgres-db -d /custom/path 13 14  # Using custom data directory
  $0 -n postgres-db --backup-only 13    # Only create backup of PostgreSQL 13
  $0 -n postgres-db --restore-only 13   # Only restore from existing backup of version 13

${YELLOW}Backups are stored in:${NC} ${BACKUP_DIR}
${YELLOW}Logs are stored in:${NC} ${LOG_FILE}
EOF
}

# Function to perform restore-only operation
restore_only() {
    local version=$1
    local dump_file="${BACKUP_DIR}/dump_v${version}.sql"

    log "INFO" "Starting restore-only operation for PostgreSQL $version"

    # Check if backup exists
    if ! verify_backup "$version"; then
        log "ERROR" "Cannot restore - backup verification failed"
        exit 1
    fi

    # Check if container is running and start if needed
    if ! check_container_status 30; then
        log "ERROR" "Cannot restore - container failed to start"
        exit 1
    fi

    # Perform restore
    if ! restore_database "$version"; then
        log "ERROR" "Database restore failed"
        exit 1
    fi

    log "INFO" "Restore-only operation completed successfully"
}

# Function to safely clean PostgreSQL data directory inside the container
clean_data_directory() {
    log "INFO" "Preparing to clean PostgreSQL data directory inside container..."

    # Check if the container is running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "INFO" "Stopping PostgreSQL service within running container..."
        docker exec "$CONTAINER_NAME" su postgres -c "pg_ctl stop -D $DATA_DIRECTORY" || true

        # Wait for PostgreSQL to shut down completely (retrying up to 10 times)
        local retries=10
        while docker exec "$CONTAINER_NAME" pg_isready -U postgres > /dev/null 2>&1 && [ $retries -gt 0 ]; do
            log "INFO" "Waiting for PostgreSQL to shut down... (${retries} retries remaining)"
            sleep 2
            retries=$((retries - 1))
        done

        if [ $retries -eq 0 ]; then
            log "ERROR" "PostgreSQL did not shut down within the expected time"
            return 1
        fi

        # Stop the container if PostgreSQL has been stopped
        log "INFO" "Stopping container..."
        docker-compose down
    else
        log "INFO" "Container is already stopped."
    fi

    # Clean data directory inside a temporary container
    log "INFO" "Cleaning PostgreSQL data directory..."
    docker-compose run --rm "$CONTAINER_NAME" sh -c "rm -rf ${DATA_DIRECTORY:?}/*"

    log "INFO" "PostgreSQL data directory cleaned inside container"
}



# Function to perform upgrade
upgrade_postgres() {
    local from_version=$1
    local to_version=$2

    log "INFO" "Starting PostgreSQL upgrade from version $from_version to $to_version"

    # Step 1: Check container status and dump current database
    if ! dump_database "$from_version"; then
        log "ERROR" "Database dump failed"
        exit 1
    fi

    # Verify backup
    if ! verify_backup "$from_version"; then
        log "ERROR" "Backup verification failed"
        exit 1
    fi

    # Step 2: Stop current container and clean data directory
    clean_data_directory

    # Step 3: Update docker-compose.yml to new version
    update_version "$to_version"

    # Step 4: Start new container
    log "INFO" "Starting new PostgreSQL container..."
    docker-compose up -d

    # Give PostgreSQL a moment to initialize
    sleep 5

    # Step 5: Restore database (includes container ready check)
    if ! restore_database "$from_version"; then
        log "ERROR" "Database restore failed"
        log "WARNING" "Rolling back to version $from_version..."
        clean_data_directory  # Clean again before rolling back
        update_version "$from_version"
        docker-compose up -d
        exit 1
    fi

    log "INFO" "PostgreSQL upgrade completed successfully"
}

# Parse command line arguments
BACKUP_ONLY=false
RESTORE_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -d|--data-dir)
            DATA_DIRECTORY="$2"
            shift 2
            ;;
        --backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        --restore-only)
            RESTORE_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --version)
            display_version
            exit 0
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Validate mandatory container name
if [ -z "$CONTAINER_NAME" ]; then
    log "ERROR" "Container name is mandatory. Use -n or --name to specify it."
    usage
    exit 1
fi

# Sanitize DATA_DIRECTORY var
DATA_DIRECTORY="${DATA_DIRECTORY%/}"

# Check remaining arguments
if [ "$BACKUP_ONLY" = true ] && [ "$#" -ne 1 ]; then
    log "ERROR" "Backup-only mode requires just the version number"
    usage
    exit 1
elif [ "$RESTORE_ONLY" = true ] && [ "$#" -ne 1 ]; then
    log "ERROR" "Restore-only mode requires just the version number"
    usage
    exit 1
elif [ "$BACKUP_ONLY" = false ] && [ "$RESTORE_ONLY" = false ] && [ "$#" -ne 2 ]; then
    log "ERROR" "Upgrade mode requires both from-version and to-version"
    usage
    exit 1
fi

# Ensure only one operation mode is selected
if [ "$BACKUP_ONLY" = true ] && [ "$RESTORE_ONLY" = true ]; then
    log "ERROR" "Cannot specify both --backup-only and --restore-only"
    usage
    exit 1
fi

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Execute requested operation
if [ "$BACKUP_ONLY" = true ]; then
    dump_database "$1"
elif [ "$RESTORE_ONLY" = true ]; then
    restore_only "$1"
elif [ "$DRY_RUN" = true ]; then
    dry_run "$1" "$2"
else
    upgrade_postgres "$1" "$2"
fi
