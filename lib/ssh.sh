#!/bin/bash

function qscp { scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@; }
function qssh { ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@; }
function lssh { HOST=$(sed 's/^[^1-9]*//' <<< "$1"); shift; qssh ubuntu@10.1.1.$HOST $@; }

function lssh_wait {
    HOSTS=$@
    PIDLIST=""

    for i in $HOSTS
    do
        ( while [ "$(lssh $i sudo whoami 2>/dev/null)" != "root" ]; do sleep 1; done ) &
        PIDLIST="$PIDLIST $!"
    done

    wait $PIDLIST
}
