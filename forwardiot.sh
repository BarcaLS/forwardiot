#!/bin/sh
# forwardiot.sh
# "an idiot who keeps forwarding shit to you" - www.urbandictionary.com
#
# Script which allows you to connect from Internet to your private host in LAN.
# It forwards trafic incoming to PUBLIC_IP:PORT to "localhost interface on PUBLIC_IP:OTHER_PORT" and then from "localhost interface on PUBLIC_IP:OTHER_PORT"
# to LOCAL_IP:PORT. OTHER_PORT is just a helper.
#
# Logging via keys is highly recommended.
# Run it e.g. via cron.

############
# Settings #
############

# IP in LAN of host on which this script is running
LOCAL_IP=`ip addr | grep 'state UP' -A2 | grep eth0 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'`

# forwarded ports: local port, remote port, helper port, IP in LAN, shell account with public IP.
# E.g.: 21 20021 40021 user@host.com
# You can specify as many of them as you wish. You can "IP in LAN" set arbitrally, it doesn't have to be IP of
# host on which this script is running.
PARAMETERS=(
	1024 1024 41024 192.168.1.23 user@host.com # local NVR
	80 20084 40084 192.168.1.82 user@host.com # WWW port on local IP camera
	21 20021 40021 $LOCAL_IP user@host.com # FTP on local NAS Synology on which forwardiot.sh is run
	55540 55540 45540 $LOCAL_IP user@host.com # FTP passive connection on local NAS Synology on which forwardiot.sh is run
)

#############
# Main Part #
#############

# check if this script is currently running
echo "::: Started."
NUMBER_OF_THIS_SCRIPTS_RUNNING=`ps ux | grep forwardiot.sh | grep -v grep | wc -l`
if [ "$NUMBER_OF_THIS_SCRIPTS_RUNNING" -gt 2 ]; then
	echo "    This script is currently running. Exiting."; exit
fi

QUANTITY_OF_PARAMETERS=${#PARAMETERS[@]}
ALLOWED_NUMBER_OF_SSH_PROCESSES=`expr $QUANTITY_OF_PARAMETERS / 5`
QUANTITY_OF_PARAMETERS=`expr $QUANTITY_OF_PARAMETERS - 1`
COUNTER_TMP=-1
ADDRESS_TO_RESET=()
while [ ! "$COUNTER_TMP" = "$QUANTITY_OF_PARAMETERS" ]
do # let's get all remote addresses
    ADDRESS_TO_RESET+=("${PARAMETERS[$COUNTER_TMP + 5]}")
    COUNTER_TMP=`expr $COUNTER_TMP + 5`
done
ADDRESS_TO_RESET=($(echo "${ADDRESS_TO_RESET[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')) # let's leave only uniqe addresses
COUNTER=0
while [ ${ADDRESS_TO_RESET[$COUNTER]} ]; do
    REMOTE_ADDRESS=${ADDRESS_TO_RESET[$COUNTER]}
    SSH_PROCESSES=`ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f $REMOTE_ADDRESS "ps ux | grep 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -g -N -L' | grep -v grep" 2>/dev/null`

    # allow only $ALLOWED_NUMBER_OF_SSH_PROCESSES ssh forwarding processes on remote host (safety rule)
    if [ "$SSH_PROCESSES" == "" ]
    then
	NUMBER_OF_SSH_PROCESSES="0"
    else
	NUMBER_OF_SSH_PROCESSES=`echo "$SSH_PROCESSES" | wc -l`
    fi
    echo "::: Maximum SSH forwarding processes allowed on $REMOTE_ADDRESS is $ALLOWED_NUMBER_OF_SSH_PROCESSES and you have already $NUMBER_OF_SSH_PROCESSES ssh processes running."
    if [ "$NUMBER_OF_SSH_PROCESSES" -gt "$ALLOWED_NUMBER_OF_SSH_PROCESSES" ]
    then
	PIDS=(`echo "$SSH_PROCESSES" | awk '{ print $2 }'`)
        COUNTER_TMP=0
        CMD_COMPLETE=""
	echo "    I kill all ssh forwarding processes on $REMOTE_ADDRESS because they're too many of them."
	while [ ${PIDS[$COUNTER_TMP]} ]; do
	    CMD_CURRENT="kill -TERM ${PIDS[$COUNTER_TMP]}; kill -CHLD ${PIDS[$COUNTER_TMP]}"
	    if [ "$COUNTER_TMP" == "0" ]; then CMD_COMPLETE="$CMD_CURRENT"; else CMD_COMPLETE="$CMD_COMPLETE; $CMD_CURRENT"; fi
	    COUNTER_TMP=`expr $COUNTER_TMP + 1`
	done
        if [ ! -z "$CMD_COMPLETE" ]; then
    	    ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f $REMOTE_ADDRESS "$CMD_COMPLETE"
	fi
    fi

    # allow only $ALLOWED_NUMBER_OF_SSH_PROCESSES ssh forwarding processes on local host (safety rule)
    NUMBER_OF_SSH_PROCESSES=`ps ux | grep 'ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R' | grep -v grep | wc -l`
    echo "::: Maximum SSH forwarding processes allowed on localhost is $ALLOWED_NUMBER_OF_SSH_PROCESSES and you have already $NUMBER_OF_SSH_PROCESSES ssh processes running."
    if [ "$NUMBER_OF_SSH_PROCESSES" -gt "$ALLOWED_NUMBER_OF_SSH_PROCESSES" ]
    then
	PIDS=(`ps ux | grep 'ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R' | grep -v grep | awk '{ print $2 }'`)
        COUNTER_TMP=0
	echo "    I kill all ssh forwarding processes on localhost because they're too many of them."
	while [ ${PIDS[$COUNTER_TMP]} ]; do
	    kill -TERM ${PIDS[$COUNTER_TMP]}; kill -CHLD ${PIDS[$COUNTER_TMP]}
	    COUNTER_TMP=`expr $COUNTER_TMP + 1`
	done
    fi

    # kill all ssh <defunct> processes on local host
    PIDS=(`ps ux | grep defunct | grep ssh | grep -v grep | awk '{ print $2 }'`)
    COUNTER_TMP=0
    echo "::: I kill all ssh <defunct> processes on local host."
    while [ ${PIDS[$COUNTER_TMP]} ]; do
	kill -TERM ${PIDS[$COUNTER_TMP]}; kill -CHLD ${PIDS[$COUNTER_TMP]}
        COUNTER_TMP=`expr $COUNTER_TMP + 1`
    done

    # kill all ssh <defunct> processes on remote host
    PIDS=(`echo "$SSH_PROCESSES" | grep defunct | awk '{ print \$2 }'`)
    COUNTER_TMP=0
    CMD_COMPLETE=""
    echo "::: I kill all ssh <defunct> processes on $REMOTE_ADDRESS."
    while [ ${PIDS[$COUNTER_TMP]} ]; do
	CMD_CURRENT="kill -TERM ${PIDS[$COUNTER_TMP]}; kill -CHLD ${PIDS[$COUNTER_TMP]}"
	if [ "$COUNTER_TMP" == "0" ]; then CMD_COMPLETE="$CMD_CURRENT"; else CMD_COMPLETE="$CMD_COMPLETE; $CMD_CURRENT"; fi
	COUNTER_TMP=`expr $COUNTER_TMP + 1`
    done
    if [ ! -z "$CMD_COMPLETE" ]; then
	ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f $REMOTE_ADDRESS "$CMD_COMPLETE"
    fi

    # port forwarding
    COUNTER_TMP=-1
    while [ ! "$COUNTER_TMP" = "$QUANTITY_OF_PARAMETERS" ]
    do
	if [ "$REMOTE_ADDRESS" == "${PARAMETERS[$COUNTER_TMP + 5]}" ]; then
	    LOCAL_PORT="${PARAMETERS[$COUNTER_TMP + 1]}"
	    REMOTE_PORT="${PARAMETERS[$COUNTER_TMP + 2]}"
	    HELPER_PORT="${PARAMETERS[$COUNTER_TMP + 3]}"
	    LOCAL_ADDRESS="${PARAMETERS[$COUNTER_TMP + 4]}"

	    echo "::: Forwarding $LOCAL_ADDRESS:$LOCAL_PORT to $REMOTE_ADDRESS:$REMOTE_PORT."
	    # check if ssh process already exists on remote host
	    PID_REMOTE=(`echo "$SSH_PROCESSES" | grep 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -g -N -L' | grep ":$HELPER_PORT" | grep "$REMOTE_PORT:" | grep -v 'grep' | awk '{ print \$2 }'`)
	    PID_LOCAL=`ps ux | grep 'ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R' | grep "$LOCAL_PORT:" | grep ":$HELPER_PORT" | grep -v 'grep' | awk '{ print \$2 }'`
	    if ([ -z "$PID_REMOTE" ] && [ -z "$PID_LOCAL" ])
	    then # ssh process doesn't exist on local host and on remote host
		echo "    Enabling forwarding."
		ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R $HELPER_PORT:$LOCAL_ADDRESS:$LOCAL_PORT $REMOTE_ADDRESS "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -g -N -L $REMOTE_PORT:localhost:$HELPER_PORT localhost" 2>/dev/null
	    else
		if ([ -z "$PID_REMOTE" ] && [ ! -z "$PID_LOCAL" ]) # ssh process doesn't exist on remote host and exists on local host
		then
		    echo "    Enabling forwarding (ssh process missing on remote host)."
		    kill -TERM $PID_LOCAL; kill -CHLD $PID_LOCAL
		    ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R $HELPER_PORT:$LOCAL_ADDRESS:$LOCAL_PORT $REMOTE_ADDRESS "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -g -N -L $REMOTE_PORT:localhost:$HELPER_PORT localhost" 2>/dev/null
		fi
		if ([ ! -z "$PID_REMOTE" ] && [ -z "$PID_LOCAL" ]) # ssh process exists on remote host and doesn't exist on local host
		then
		    echo "    Enabling forwarding (ssh process missing on local host)."
		    CMD="kill -TERM $PID_REMOTE; kill -CHLD $PID_REMOTE"
		    ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f $REMOTE_ADDRESS "$CMD"
		    ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -f -A -R $HELPER_PORT:$LOCAL_ADDRESS:$LOCAL_PORT $REMOTE_ADDRESS "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -g -N -L $REMOTE_PORT:localhost:$HELPER_PORT localhost" 2>/dev/null
		fi
		if ([ ! -z "$PID_REMOTE" ] && [ ! -z "$PID_LOCAL" ]) # ssh process exists on local and remote hosts
		then
		    echo "    Forwarding already enabled, skipping."		
		fi
	    fi
	fi
	COUNTER_TMP=`expr $COUNTER_TMP + 5`
    done
    COUNTER=`expr $COUNTER + 1`
done

echo "::: Ended."
