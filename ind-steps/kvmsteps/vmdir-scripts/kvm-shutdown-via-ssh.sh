#!/bin/bash

source "$(dirname $(readlink -f "$0"))/bashsteps-defaults-jan2017-check-and-do.source" || exit

kvm_is_running()
{
    kvmpid="$(cat "$DATADIR/runinfo/kvm.pid" 2>/dev/null)" &&
	[ -d /proc/"$(< "$DATADIR/runinfo/kvm.pid")" ]
}

: ${SSHUSER:=$(cat "$DATADIR/sshuser" 2>/dev/null)}

maybesudo=""
[ "$SSHUSER" != "root" ] && maybesudo="sudo "

(
    $starting_step "Send \"${maybesudo}shutdown -h now\" via ssh"
    ! kvm_is_running
    $skip_step_if_already_done ; set -e
    "$DATADIR/ssh-shortcut.sh" $maybesudo shutdown -h now || :  # why does this return rc=255??
) ; $iferr_exit

: ${WAITFORSHUTDOWN:=5 5 2 2 2 5 5 10 10 30 60} # set WAITFORSHUTDOWN to "0" to not wait
(
    $starting_step "Wait for KVM to exit"
    [ "$WAITFORSHUTDOWN" = "0" ] || ! kvm_is_running
    $skip_step_if_already_done
    WAITFORSHUTDOWN="${WAITFORSHUTDOWN/[^0-9 ]/}" # make sure its only a list of integers
    waitfor="5"
    while true; do
	kvm_is_running || break # sets $kvmpid
	# Note that the </dev/null above is necessary so nc does not
	# eat the input for the next line
	read -d ' ' nextwait # read from list
	[ "$nextwait" == "0" ] && reportfailed "KVM process did not exit"
	[ "$nextwait" != "" ] && waitfor="$nextwait"
	echo "Waiting for $waitfor seconds for KVM process $kvmpid to exit"
	sleep "$waitfor"
    done <<<"$WAITFORSHUTDOWN"
    kvm_is_running || rm $DATADIR/runinfo/kvm.pid
) ; $iferr_exit
