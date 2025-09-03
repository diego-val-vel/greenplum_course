#!/bin/bash
echo "Executing initialization shell script"
psql -U ${GREENPLUM_USER} -h $(hostname) -d ${GREENPLUM_DATABASE_NAME} -c "INSERT INTO test_initialization (name) VALUES ('Added via shell script');"
echo "Shell script executed successfully!"