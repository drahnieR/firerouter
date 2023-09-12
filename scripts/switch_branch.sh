#!/bin/bash

set -e

: ${FIREROUTER_HOME:=/home/pi/firerouter}
: ${FIREROUTER_HIDDEN:=/home/pi/.router}
MGIT=$(PATH=/home/pi/scripts:$FIREROUTER_HOME/scripts; /usr/bin/which mgit||echo git)
source ${FIREROUTER_HOME}/platform/platform.sh
CMD=$(basename $0)

usage() {
    cat <<EOU
usage: $CMD <branch>
example:

    # switch to master
    $CMD master

    # switch to release
    $CMD release_6_0

    # switch to beta
    $CMD beta_6_0

    # switch to alpha
    $CMD beta_7_0
EOU
}

err() {
    msg="$@"
    echo "ERROR: $msg" >&2
}

switch_branch() {
    cur_branch=$1
    tgt_branch=$2
    if [[ "$cur_branch" == "$tgt_branch" ]]; then
      exit 0
    fi
    remote_branch=$(map_target_branch $tgt_branch)
    # firerouter repo
    ( cd $FIREROUTER_HOME
    git config remote.origin.fetch "+refs/heads/$remote_branch:refs/remotes/origin/$remote_branch"
    $MGIT fetch origin $remote_branch
    git checkout -f -B $tgt_branch origin/$remote_branch
    )
}

set_redis_flag() {
    redis_flag=
    case $1 in
        release_*)
            redis_flag=1
            ;;
        beta_7_*)
            redis_flag=4
            ;;
        beta_6_*)
            redis_flag=2
            ;;
        master)
            redis_flag=3
            ;;
    esac
    test -n "$redis_flag" || return 1
    redis-cli hset fr:sys:config branch.changed $redis_flag &>/dev/null
}

# --------------
# MAIN goes here
# --------------

test $# -gt 0 || {
    usage
    err "branch is required"
    exit 1
}

branch=$1
cur_branch=$(git rev-parse --abbrev-ref HEAD)
switch_branch $cur_branch $branch || exit 1
rm -f "$FIREROUTER_HIDDEN/config/.no_auto_upgrade"
# remove prepared flag file to trigger prepare_env during next init_network_config
rm -f /dev/shm/firerouter.prepared
# set node_modules link to the proper directory
NODE_MODULES_PATH=$(get_node_modules_dir)
if [[ -h ${FIREROUTER_HOME}/node_modules ]]; then
  if [[ $(readlink ${FIREROUTER_HOME}/node_modules) != $NODE_MODULES_PATH ]]; then
    ln -sfT $NODE_MODULES_PATH ${FIREROUTER_HOME}/node_modules
  fi
fi

if [[ $NETWORK_SETUP == "yes" ]]; then
  sudo cp /home/pi/firerouter/scripts/firerouter.service /etc/systemd/system/.
  sudo cp /home/pi/firerouter/scripts/fireboot.service /etc/systemd/system/.
else
  sudo cp /home/pi/firerouter/scripts/fireboot_standalone.service /etc/systemd/system/fireboot.service
fi
sudo cp /home/pi/firerouter/scripts/firereset.service /etc/systemd/system/.
sudo systemctl daemon-reload

sync
logger "FireRouter: SWITCH branch from $cur_branch to $branch"
