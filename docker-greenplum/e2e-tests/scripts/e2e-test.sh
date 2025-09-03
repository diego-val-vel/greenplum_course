#!/usr/bin/env bash
set -Eeuo pipefail

GP_USER=${GREENPLUM_USER:-gpadmin}
GP_PASSWORD=${GREENPLUM_PASSWORD:-}
GP_MASTER_PORT=${EXPOSE_MASTER_PORT:-5432}
GP_RESTORE_MASTER_PORT=${EXPOSE_RESTORE_MASTER_PORT:-6432}
GP_DB_NAME=${GREENPLUM_DB_NAME:-demo}
GP_VER=${GP_VERSION:-}

WALG_CONFIG="/tmp/wal-g.yaml"
WALG_RESTORE_CONFIG="/tmp/wal-g_restore.json"

PRIMARY_MASTER_CONTAINER="master"
RESTORE_MASTER_CONTAINER="master-restore"
RP_NAME="rp1"

# Check password is set
if [ -z "$GP_PASSWORD" ]; then
    echo "ERROR - GP_PASSWORD variable is not set"
    exit 1
fi

# Check GP_VERSION is set
if [ -z "$GP_VERSION" ]; then
    echo "ERROR - GP_VERSION variable is not set"
    exit 1
fi

exec_sql() {
    local port=$1
    local sql=$2
    PGPASSWORD=${GP_PASSWORD} psql -h localhost -U ${GP_USER} -d ${GP_DB_NAME} -p ${port} -t -c "${sql}"
}

exec_docker(){
    local container_name=$1
    local cmd=$2
    docker exec ${container_name} su - ${GP_USER} -c "${cmd}"
}

wait_for_service() {
    local port=$1
    local max_attempts=${2:-10}

    for i in $(seq 1 ${max_attempts}); do
        if exec_sql ${port} "SELECT 1;" >/dev/null 2>&1; then
            echo "INFO - Cluster ready"
            return 0
        fi
        echo "INFO - Waiting cluster startup ($i/${max_attempts})"
        sleep 10
    done
    echo "ERROR - Cluster failed to start within timeout"
    return 1
}

get_table_data() {
    local port=$1    
    exec_sql ${port} "
    SELECT 'walg_ao' AS table_name, COUNT(*) AS count FROM walg_ao 
    UNION ALL 
    SELECT 'walg_co' AS table_name, COUNT(*) AS count FROM walg_co 
    UNION ALL 
    SELECT 'walg_heap' AS table_name, COUNT(*) AS count FROM walg_heap 
    ORDER BY table_name;"
}

switch_wal() {
    local port=$1
    case "${GP_VERSION}" in
        "6")
            exec_sql ${port} "SELECT pg_switch_xlog() UNION ALL SELECT pg_switch_xlog() FROM gp_dist_random('gp_id');"
            ;;
        "7")
            exec_sql ${port} "SELECT pg_switch_wal() UNION ALL SELECT pg_switch_wal() FROM gp_dist_random('gp_id');"
            ;;
        *)
            echo "ERROR - Unsupported Greenplum version: ${GP_VERSION}"
            exit 1
            ;;
    esac
}

compare_data() {
    local primary_data=$(get_table_data ${GP_MASTER_PORT})
    local standby_data=$(get_table_data ${GP_RESTORE_MASTER_PORT})

    echo "INFO - Primary cluster data:"
    echo "$primary_data"
    echo "INFO - Standby cluster data:"
    echo "$standby_data"

    if [ "$primary_data" = "$standby_data" ]; then
        echo "INFO - Data matches between primary and standby clusters"
    else
        echo "ERROR - Data mismatch between primary and standby clusters"
        exit 1
    fi
}

list_backup_and_rp() {
    local container=$1

    echo "INFO - Show backup list"
    exec_docker ${container} "wal-g backup-list --config ${WALG_CONFIG}"
    echo "INFO - Show restore point list"
    exec_docker ${container} "wal-g restore-point-list --config ${WALG_CONFIG}"
}

get_backup_name() {
    local container=$1

    local backup_name=$(exec_docker ${container} "wal-g backup-list --config ${WALG_CONFIG}" | tail -n 1 | awk '{print $1}')
    if [ -z "$backup_name" ]; then
        echo "ERROR - backup not found"
        return 1
    fi
    echo "$backup_name"
}

restore_backup() {
    local backup_name=$1
    local restore_point=${2:-}
    
    echo "INFO - Stopping standby cluster"
    exec_docker ${RESTORE_MASTER_CONTAINER} "gpstop -a -M fast"  

    echo "INFO - Cleaning data"
    exec_docker ${RESTORE_MASTER_CONTAINER} "rm -rf /data/master/gpseg-1/*"
    exec_docker ${RESTORE_MASTER_CONTAINER} "gpssh -h segment1 -h segment2 'rm -rf /data/0*/primary/gpseg*/*'"

    echo "INFO - Restoring from backup"
    if [ -n "$restore_point" ]; then
        exec_docker ${RESTORE_MASTER_CONTAINER} "wal-g backup-fetch ${backup_name} --restore-point ${restore_point} --config ${WALG_CONFIG} --restore-config=${WALG_RESTORE_CONFIG}"
    else
        exec_docker ${RESTORE_MASTER_CONTAINER} "wal-g backup-fetch ${backup_name} --config ${WALG_CONFIG} --restore-config=${WALG_RESTORE_CONFIG}"
    fi

    echo "INFO - Configuring restored cluster"
    exec_docker ${RESTORE_MASTER_CONTAINER} "sed -i 's|^archive_command=.*timeout.*wal-g.*|#&|' /data/master/gpseg-1/postgresql.conf"
    exec_docker ${RESTORE_MASTER_CONTAINER} "gpssh -h segment1 -h segment2 'find /data -name postgresql.conf -exec sed -i \"s|^archive_command=.*timeout.*wal-g.*|#&|\" {} \;'"
    exec_docker ${RESTORE_MASTER_CONTAINER} "echo 'host all all 0.0.0.0/0 md5' >> /data/master/gpseg-1/pg_hba.conf"
    exec_docker ${RESTORE_MASTER_CONTAINER} "echo 'host all all ::0/0 md5' >> /data/master/gpseg-1/pg_hba.conf"

    echo "INFO - Starting restored cluster"
    exec_docker ${RESTORE_MASTER_CONTAINER} "gpstart -a -t 180"
}

echo "INFO - Check primary Greenplum cluster"
sleep 90
echo "INFO - Waiting cluster startup on port ${GP_MASTER_PORT}"
wait_for_service ${GP_MASTER_PORT}
echo "INFO - Waiting cluster startup on port ${GP_RESTORE_MASTER_PORT}"
wait_for_service ${GP_RESTORE_MASTER_PORT}

# Test restore full backup
echo "INFO - Create backup full backup on primary cluster"
exec_docker ${PRIMARY_MASTER_CONTAINER} "wal-g backup-push --config ${WALG_CONFIG}"
echo "INFO - Switch WALs on primary cluster"
switch_wal ${GP_MASTER_PORT}
echo "INFO - Get backup name for restore"
restore_bckp_name=$(get_backup_name ${PRIMARY_MASTER_CONTAINER})
echo "INFO - Restore full backup on standby cluster"
restore_backup ${restore_bckp_name}
echo "INFO - Waiting cluster startup on port ${GP_RESTORE_MASTER_PORT}"
wait_for_service ${GP_RESTORE_MASTER_PORT}
echo "INFO - Compare data between primary and standby clusters"
compare_data

# Test restore point
echo "INFO - Insert data into walg_ao on primary cluster"
exec_sql ${GP_MASTER_PORT} "INSERT INTO walg_ao SELECT i, i FROM generate_series(1,200) i;"
echo "INFO - Insert data into walg_co on primary cluster"
exec_sql ${GP_MASTER_PORT} "INSERT INTO walg_co SELECT i, i FROM generate_series(1,100) i;"
echo "INFO - Create restore point on primary cluster"
exec_docker ${PRIMARY_MASTER_CONTAINER} "wal-g create-restore-point ${RP_NAME} --config ${WALG_CONFIG}"
echo "INFO - Switch WALs on primary cluster"
switch_wal ${GP_MASTER_PORT}
echo "INFO - Get backup name for restore point"
restore_bckp_name=$(get_backup_name ${PRIMARY_MASTER_CONTAINER})
echo "INFO - Restore restore-point on standby cluster"
restore_backup ${restore_bckp_name} ${RP_NAME}
echo "INFO - Waiting cluster startup on port ${GP_RESTORE_MASTER_PORT}"
wait_for_service ${GP_RESTORE_MASTER_PORT}
echo "INFO - Compare data after restore point ${RP_NAME} between primary and standby clusters"
compare_data

echo "INFO - Greenplum wal-g e2e tests completed successfully"
