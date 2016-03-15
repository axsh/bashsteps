#!/bin/bash

source "$(dirname $(readlink -f "$0"))/../simple-defaults-for-bashsteps.source"

if [[ "$DATADIR" != /* ]]; then
    # Choose directory of symbolic link by default
    DATADIR="$LINKCODEDIR"
fi

source "$DATADIR/datadir.conf"

[ -d "$DATADIR/runinfo" ] || mkdir "$DATADIR/runinfo"
: ${KVMMEM:=1024}
: ${VNCPORT:=$(( 11100 - 5900 ))}
# Note: EXTRAHOSTFWD can be set to something like ",hostfwd=tcp::$18080-:8888"
calculate_ports()
{
    echo ${VNCPORT} >"$DATADIR/runinfo/port.vnc"
    echo ${SSHPORT:=$(( VNCPORT + 22 ))} >"$DATADIR/runinfo/port.ssh"
    echo ${MONPORT:=$(( VNCPORT + 30 ))} >"$DATADIR/runinfo/port.monitor"
    echo ${SERPORT:=$(( VNCPORT + 40 ))} >"$DATADIR/runinfo/port.serial"
}
calculate_ports

(
    $starting_group "Boot KVM"
    (
	$starting_step "Find qemu binary"
	[ "$KVMBIN" != "" ] && [ -f "$KVMBIN" ]
	$skip_step_if_already_done
	binlist=(
	    /usr/libexec/qemu-kvm
	    /usr/bin/qemu-kvm
	)
	for i in "${binlist[@]}"; do
	    if [ -f "$i" ]; then
		echo ": \${KVMBIN:=$i}" >>"$DATADIR/datadir.conf"
		exit 0
	    fi
	done
	exit 1
    ) ; prev_cmd_failed
    source "$DATADIR/datadir.conf"

    build-cmd-line() # a function, not a step
    {
	cat <<EOF
	    $KVMBIN

	    -m $KVMMEM
	    -smp 2
	    -name kvmsteps

	    -monitor telnet:127.0.0.1:$MONPORT,server,nowait
	    -no-kvm-pit-reinjection
	    -vnc 127.0.0.1:$VNCPORT
	    -serial telnet:127.0.0.1:$SERPORT,server,nowait
	    -drive file=$IMAGEFILENAME,id=vol-tu3y7qj4-drive,if=none,serial=vol-tu3y7qj4,cache=none,aio=native
	    -device virtio-blk-pci,id=vol-tu3y7qj4,drive=vol-tu3y7qj4-drive,bootindex=0,bus=pci.0,addr=0x4

	    -net nic,vlan=0,macaddr=52:54:00:65:28:dd,model=virtio,addr=10
	    -net user,vlan=0,hostfwd=tcp::$SSHPORT-:22$EXTRAHOSTFWD
EOF
    }

    portcollision()
    {
	erroutput="$(cat "$DATADIR/runinfo/kvm.stderr")"
	for i in "could not set up host forwarding rule" \
		     "Failed to bind socket"
	do
	    if [[ "$erroutput" == *${i}* ]]; then
		echo "Failed to bind a socket, probably because it is already in use." 1>&2
		echo "Will try a different set of port numbers." 1>&2
		# pick a random number between 100 and 300, then add two zeros
		target="$(( $RANDOM % 200 + 100 ))00"
		VNCPORT="$(( target - 5900 ))"
		SSHPORT=""  MONPORT=""  SERPORT=""
		calculate_ports

		# value is saved, so that the VM will attempt to use same ports next time
		echo "VNCPORT=$VNCPORT" >>"$DATADIR/datadir.conf"
		return 0 # yes, a port collision, so retry
	    fi
	done
	return 1 # no, so maybe KVM started OK
    }

    kvm_is_running()
    {
	pid="$(cat "$DATADIR/runinfo/kvm.pid" 2>/dev/null)" &&
	    [ -d /proc/"$(< "$DATADIR/runinfo/kvm.pid")" ]
    }

    (
	$starting_step "Start KVM process"
	kvm_is_running
	$skip_step_if_already_done
	set -e
	: ${KVMBIN:?} ${IMAGEFILENAME:?} ${KVMMEM:?}
	: ${VNCPORT:?} ${SSHPORT:?} ${MONPORT:?} ${SERPORT:?}
	set -e
	cd "$DATADIR"
	repeat=true
	while $repeat; do
	    repeat=false
	    ( # using a temporary subprocess to supress job control messages
		kpat=( $(build-cmd-line) )
		setsid "$ORGCODEDIR/../monitor-process.sh" runinfo/kvm "${kpat[@]}" &
	    )
	    for s in ${kvmearlychecks:=1 1 1 1 1} ; do # check early errors for 5 seconds
		sleep "$s"
		if ! kvm_is_running; then
		    portcollision && { repeat=true; break ; }
		    reportfailed "KVM exited early. Check runinfo/kvm.stderr for clues."
		fi
	    done
	    sleep 0.5
	done
    ) ; prev_cmd_failed
    source "$DATADIR/datadir.conf"
    SSHPORT=""  MONPORT=""  SERPORT="" # TODO: make this not needed
    calculate_ports

    ssh_is_active()
    {
	# TODO: make sure this generalizes to different version of nc
	[[ "$(nc 127.0.0.1 -w 3 "$SSHPORT" </dev/null)" == *SSH* ]]
    }

    : ${WAITFORSSH:=5 2 1 1 1 1 1 1 1 1 5 10 20 30 120} # set WAITFORSSH to "0" to not wait
    (
	$starting_step "Wait for SSH port response"
	[ "$WAITFORSSH" = "0" ] || kvm_is_running && ssh_is_active
	$skip_step_if_already_done
	WAITFORSSH="${WAITFORSSH/[^0-9 ]/}" # make sure its only a list of integers
	waitfor="5"
	while true; do
	    ssh_is_active && break
	    # Note that the </dev/null above is necessary so nc does not
	    # eat the input for the next line
	    read -d ' ' nextwait # read from list
	    [ "$nextwait" == "0" ] && reportfailed "SSH port never became active"
	    [ "$nextwait" != "" ] && waitfor="$nextwait"
	    echo "Waiting for $waitfor seconds for ssh port ($SSHPORT) to become active"
	    sleep "$waitfor"
	done <<<"$WAITFORSSH"
    ) ; prev_cmd_failed
)
