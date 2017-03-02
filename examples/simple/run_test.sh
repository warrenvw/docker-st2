#!/bin/bash

set -e
set -u
set -x

# start mongo
docker-compose up -d mongo

# wait for mongo to be ready
docker-compose exec mongo bash -c "$(cat << EOF
  while true; do
    mongo < <(echo "{ ping: 1 }") > /dev/null 2>&1 && break
    sleep 1
  done
EOF
)"

# setup mongo
docker-compose exec mongo bash -c "$(cat << EOF
mongo << SCRIPT
    use admin;
    db.createUser({
        user: "admin",
        pwd: "StackStorm",
        roles: [
            { role: "userAdminAnyDatabase", db: "admin" }
        ]
    });
    use st2;
    db.createUser({
        user: "stackstorm",
        pwd: "StackStorm",
        roles: [
            { role: "readWrite", db: "st2" }
        ]
    });
    quit();
SCRIPT
EOF
)"

# start postgres
docker-compose up -d postgres

# wait for postgres to be ready
docker-compose exec --user postgres postgres bash -c "$(cat << EOF
  while true; do
    psql -h postgres. -c "select 1;" > /dev/null 2>&1 && break
    sleep 1
  done
EOF
)"

# setup postgres
docker-compose exec --user postgres postgres psql -c "CREATE ROLE mistral WITH CREATEDB LOGIN ENCRYPTED PASSWORD 'StackStorm';"
docker-compose exec --user postgres postgres psql -c "CREATE DATABASE mistral OWNER mistral;"

# start all containers
docker-compose up -d

# wait for a while to settle down...
docker-compose exec st2 bash -x -c "$(cat << EOF
  while true; do
    st2ctl status | grep PID && break
    sleep 10
  done
EOF
)"

# register default packs
docker-compose exec st2 st2ctl reload --register-all

# setup virtualenvs
docker-compose exec st2 st2ctl reload --register-setup-virtualenvs

# get examples
docker-compose exec st2 bash -c "$(cat << EOF
  cd /tmp
  git clone --depth=1 https://github.com/StackStorm/st2
  cp -a /tmp/st2/contrib/examples /opt/stackstorm/packs
  st2ctl reload --register-all --register-setup-virtualenvs
EOF
)"

# ready to go!
docker-compose exec st2 st2 run core.local -- date -R
docker-compose exec st2 st2 execution list
docker-compose exec st2 st2 run core.remote hosts="remote1,remote2" -- uname -a
docker-compose exec st2 st2 run examples.mistral_examples

