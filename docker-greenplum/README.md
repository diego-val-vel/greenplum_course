# docker-greenplum

[![build-gpdb6](https://github.com/woblerr/docker-greenplum/actions/workflows/build-gpdb6.yml/badge.svg)](https://github.com/woblerr/docker-greenplum/actions/workflows/build-gpdb6.yml)
[![build-gpdb7](https://github.com/woblerr/docker-greenplum/actions/workflows/build-gpdb7.yml/badge.svg)](https://github.com/woblerr/docker-greenplum/actions/workflows/build-gpdb7.yml)

This project provides a Docker image for running Greenplum Database (GPDB) in containers. It supports both single-node and multi-node deployments. The image can be use for development, testing, and learning purposes.

The Greenplum in docker provides the following features:
- single-node deployment;
- master and segments deployment;
- support for segment mirroring;
- gpperfmon (GPDB 6 only);
- diskquota;
- gpbackup/gprestore;
- gpbackup-s3-plugin;
- gpbackman;
- PXF (Platform Extension Framework);
- custom initialization scripts;
- WAL-G (physical backups).

Environment variables supported by this image:

* `TZ` - container's time zone, default `Etc/UTC`;
* `GREENPLUM_USER` - non-root user name for execution of the command, default `gpadmin`;
* `GREENPLUM_UID` - UID of `${GREENPLUM_USER}` user, default `1001`;
* `GREENPLUM_GROUP` - group name of `${GREENPLUM_USER}` user, default `gpadmin`;
* `GREENPLUM_GID` - GID of `${GREENPLUM_USER}` user, default `1001`;
* `GREENPLUM_DEPLOYMENT` - Greenplum deployment type, default `singlenode`, available values: `singlenode`, `master`, `segment`;
* `GREENPLUM_DATA_DIRECTORY` - Greenplum data directory location, default `/data`;
* `GREENPLUM_SEG_PREFIX` - Greenplum segment prefix, default `gpseg`;
* `GREENPLUM_DATABASE_NAME` - Greenplum database name, default `demo`, this database will be created during the initialization;
* `GREENPLUM_GPPERFMON_ENABLE` - enable gpperfmon (GPDB 6 only), default `false`;
* `GREENPLUM_DISKQUOTA_ENABLE` - enable diskquota, default `false`;
* `GREENPLUM_PXF_ENABLE` - enable PXF, default `false`;
* `GREENPLUM_WALG_ENABLE` - enable WAL-G, default `false`;

Required environment variables:
* `GREENPLUM_PASSWORD` - password for `${GREENPLUM_USER}` user, **required**;
* `GREENPLUM_GPMON_PASSWORD` - password for `gpmon` user, **required** when `GREENPLUM_GPPERFMON_ENABLE` is `true`;

## Build matrix

The repository contains information for the last available versions. For specific version, you can build your own image using the [Build](#build) section.

Greenplum 6:
| GPDB Version | Ubuntu 22.04 | Oracle Linux 8 | Platform |
|---|---|---| ---|
| 6.27.1| `6.27.1`, `6.27.1-ubuntu22.04` | `6.27.1-oraclelinux8` | `linux/amd64`, `linux/arm64` |

Greenplum 7:
| GPDB Version | Ubuntu 22.04 | Oracle Linux 8 | Platform |
|---|---|---| ---|
| 7.1.0| `7.1.0`, `7.1.0-ubuntu22.04` | `7.1.0-oraclelinux8` |  `linux/amd64`, `linux/arm64` |

## Pull
Change `tag` to the version you need.

* Docker Hub:

```bash
docker pull woblerr/greenplum:tag
```

* GitHub Registry:

```bash
docker pull ghcr.io/woblerr/greenplum:tag
```

## Run

You will need to mount the necessary directories or files inside the container (or use this image to build your own on top of it).

### Simple

```bash
docker run -p 5432:5432 -e GREENPLUM_PASSWORD=gparray -d greenplum:6.27.1
```

Connect to Greenplum:

```bash
psql -h localhost -p 5432 -U gpadmin demo
```

### Docker Secrets
As an alternative to passing sensitive information via environment variables, `_FILE` may be appended to `GREENPLUM_PASSWORD` and `GREENPLUM_GPMON_PASSWORD` environment variables. In particular, this can be used to load passwords from Docker secrets stored in `/run/secrets/<secret_name>` files. 

For example:
```bash
docker run -p 5432:5432 -e GREENPLUM_PASSWORD_FILE=/run/secrets/gpdb_password -d greenplum:6.27.1
```

### Initialization Scripts

The image supports running custom initialization `*.sql` or `*.sh` scripts after Greenplum was started. Place your scripts in the `/docker-entrypoint-initdb.d` directory inside the container.

Scripts in `/docker-entrypoint-initdb.d` are executed only if a container is started with an empty data directory; any pre-existing database will remain untouched when the container is started.

#### Script Execution Process

Scripts are processed as follows:
- **SQL scripts** (`*.sql`): Executed using `psql` with the following options:
  - Executed for the database specified in `GREENPLUM_DATABASE_NAME`.
  - Run with `-v ON_ERROR_STOP=1` flag.
  - Run with `--no-psqlrc`.
  - Connected as the `GREENPLUM_USER`.
- **Shell scripts** (`*.sh`):
  - If the script has executable permissions, it is executed directly.
  - If not executable, it is sourced.
- **Other files**: Files with other extensions are ignored.

Example SQL initialization script `00_init.sql`:

```sql
CREATE TABLE test_initialization (
  id serial PRIMARY KEY,
  name text,
  created_at timestamp DEFAULT current_timestamp
);

INSERT INTO test_initialization (name) VALUES ('Initialized via sql script');
```
Example shell script `01_init.sh`:

```bash
#!/bin/bash
echo "Executing initialization shell script"
psql -U ${GREENPLUM_USER} -h $(hostname) -d ${GREENPLUM_DATABASE_NAME} -c "INSERT INTO test_initialization (name) VALUES ('Added via shell script');"
echo "Shell script executed successfully!"
```

You can mount your initialization scripts directory to the container:

```bash
docker run -p 5432:5432 \
  -e GREENPLUM_PASSWORD=gparray \
  -v $(pwd)/docs/custom_init_scripts:/docker-entrypoint-initdb.d \
  -d greenplum:6.27.1
```

Or build a custom image:

```bash
FROM greenplum:6.27.1
COPY docs/custom_init_scripts/* /docker-entrypoint-initdb.d/
```

#### WAL-G configuration

When `GREENPLUM_WALG_ENABLE=true`, WAL-G is installed and available, but you need to configure it manually or use initialization scripts to set up `archive_command` and other parameters.


```bash
docker run -p 5432:5432 \
  -e GREENPLUM_PASSWORD=gparray \
  -e GREENPLUM_WALG_ENABLE=true \
  -v $(pwd)/wal-g.yaml:/tmp/wal-g.yaml \
  -v $(pwd)/wal-g_init.sh:/docker-entrypoint-initdb.d/wal-g_init.sh \
  -d greenplum:6.27.1
```

Where init scripts for WAL-G looks like:
```bash
#!/bin/bash
echo "Configuring wal-g archive_command"
USER=${GREENPLUM_USER} gpconfig -c archive_command -v "wal-g seg wal-push %p --content-id=%c --config /tmp/wal-g.yaml"
USER=${GREENPLUM_USER} gpconfig -c archive_timeout -v 600 --skipvalidation
USER=${GREENPLUM_USER} gpstop -u
```

### Docker Compose
#### Prepare

Prepare password files (**set your own passwords**):
```bash
echo "gparray" > docker-compose/secrets/gpdb_password
echo "changeme" > docker-compose/secrets/gpmon_password
```

For correct start docker compose, configs should be mounted to `/tmp`.
It's valid for `gpinitsystem_config`, `hostfile_gpinitsystem` and `authorized_keys` files.

SSH rsa keys should be mounted to `/home/${GREENPLUM_USER}/.ssh/` directory.
Master mounts:
```yaml
    volumes:
      - ./conf/${CONFIG_FOLDER}/gpinitsystem_config_no_mirrors:/tmp/gpinitsystem_config
      - ./conf/hostfile_gpinitsystem:/tmp/hostfile_gpinitsystem
      - ./conf/ssh/id_rsa:/home/gpadmin/.ssh/id_rsa
      - ./conf/ssh/id_rsa.pub:/home/gpadmin/.ssh/id_rsa.pub
```
Segments mounts:
```yaml
    volumes:
       - ./conf/ssh/authorized_keys:/tmp/authorized_keys
```

The image version and `CONFIG_FOLDER` variable should be set in the `.env` file. See the example `.env` file in the `docker-compose` directory.

#### Run
Run  cluster with 1 master and 2 segments without mirroring:
```bash
docker compose -f ./docker-compose/docker-compose.no_mirrors.yaml up -d
```

Run cluster with persistent storage:
```bash
docker compose -f ./docker-compose/docker-compose.no_mirrors_persistent.yaml up -d
```

Run cluster with 1 master and 2 segments with mirroring:
```bash
docker compose -f ./docker-compose/docker-compose.with_mirrors.yaml up -d
```

## Build

For Ubuntu based images:
```bash
make build_gpdb_6_ubuntu TAG_GPDB_6=6.27.1
```
```bash
make build_gpdb_7_ubuntu TAG_GPDB_7=7.1.0
```

For Oracle Linux based images:
```bash
make build_gpdb_6_oraclelinux TAG_GPDB_6=6.27.1
```
```bash
make build_gpdb_7_oraclelinux TAG_GPDB_7=7.1.0
```

Simple manual build:
```bash
docker buildx build -f docker/ubuntu22.04/6/Dockerfile -t greenplum:6.27.1 .
```

Manual build with specific component version for `linux/amd64` platform:
```bash
docker buildx build --platform linux/amd64 -f docker/ubuntu22.04/6/Dockerfile --build-arg GPDB_VERSION=6.27.1 -t greenplum:6.27.1 .
```

Manual build with specific component versions for `linux/amd64` and `linux/arm64` platforms:
```bash
docker buildx build --platform linux/amd64,linux/arm64 -f docker/ubuntu22.04/6/Dockerfile --build-arg GPDB_VERSION=6.27.1 --build-arg DISKQUOTA_VERSION=2.3.0 --build-arg GPBACKUP_VERSION=1.30.5 -t greenplum:6.27.1 .
```

## Running tests
Run the end-to-end tests:
```bash
make test-e2e
```
See [tests description](./e2e-tests/README.md).
