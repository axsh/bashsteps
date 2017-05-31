#!/bin/bash

source "$(dirname $(readlink -f "$0"))/bashsteps-defaults-jan2017-check-and-do.source" || exit

[ -d "$DATADIR/runinfo" ] || mkdir "$DATADIR/runinfo"  # TODO: move inside a step
: ${KVMMEM:=1024}
: ${VNCPORT:=$(( 11100 - 5900 ))}
# Note: EXTRAHOSTFWD can be set to something like ",hostfwd=tcp::18080-:8888"
#       EXTRAHOSTFWDREL works the same, except the first port number
#       after each hostfwd=tcp gets replaced with $VNCPORT added to that number.
#       Therefore, using EXTRAHOSTFWDREL lets this script try different ports
#       whenever there is a port collision.

calculate_ports()
{
    echo ${VNCPORT} >"$DATADIR/runinfo/port.vnc"
    echo ${SSHPORT:=$(( VNCPORT + 22 ))} >"$DATADIR/runinfo/port.ssh"
    echo ${MONPORT:=$(( VNCPORT + 30 ))} >"$DATADIR/runinfo/port.monitor"
    echo ${SERPORT:=$(( VNCPORT + 40 ))} >"$DATADIR/runinfo/port.serial"
    rewriteme="${EXTRAHOSTFWDREL:=}"  # e.g. ",hostfwd=tcp::80-:8888,...."
    hostfwdrel=""
    while [[ "$rewriteme" == *hostfwd=tcp* ]]; do
	portatfront="${rewriteme#*hostfwd=tcp:*:}"   # e.g. "80-:8888,...."
	afterport="${portatfront#*-}"  # e.g. ":8888,...."
	theport="${portatfront%$afterport}"  # e.g. 80-
	theport="${theport%-}"  # e.g. 80
	if [ "$theport" == "" ] || [ "${theport//[0-9]/}" != "" ]; then
	    reportfailed "Non digit character in port number in $EXTRAHOSTFWDREL"
	fi
	hostfwdrel="$hostfwdrel${rewriteme%$portatfront}"  # e.g. ",hostfwd=tcp::"
	hostfwdrel="$hostfwdrel$(( theport + VNCPORT ))"  # e.g. ",hostfwd=tcp::18080"
	rewriteme="-$afterport"  # e.g. "-:8888,...."
    done
    hostfwdrel="$hostfwdrel$rewriteme"  # append rest
}
calculate_ports

(
    $starting_group "Boot KVM"
    (
	$starting_step "Find qemu binary"
	: ${KVMBIN:=} # set -u workaround
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
    ) ; $iferr_exit
    source "$DATADIR/datadir.conf"

    # TODO: decide if it is worth generalizing kvmsteps to deal with cases like this:
    : ${mcastPORT:="none"}  ${mcastMAC:="52:54:00:12:00:00"}
    : ${mcastnet="-net nic,vlan=1,macaddr=$mcastMAC  -net socket,vlan=1,mcast=239.255.10.10:$mcastPORT"}

    # If mcastnet is set to "", the above line will leave it that way , so
    # export mcastnet='' can be used to boot with no second device.
    # But this is a bit tricky (i.e ${var=value} vs ${var:=value} ), so
    # the following allows for more explicit code.
    [[ "$mcastnet" == *none* ]] && mcastnet=''

    : ${tapMAC:=''} ${bridgeNAME:=''}  # workaround because set -u is in effect
    : ${bridgetapnet="-net nic,vlan=1,macaddr=$tapMAC  -net bridge,br=$bridgeNAME,vlan=1"}
    [[ "$bridgeNAME" == "" ]] && bridgetapnet=''

    : ${KVMVMNAME:=} # set -u workaround
    if [ "$KVMVMNAME" == "" ]; then
	# name the VM after that last two directory elements
	KVMVMNAME="$(
	   IFS="/"
	   read -a pathparts <<<"$DATADIR"
           IFS="-"
           echo "kvmsteps-${pathparts[*]: -2}"
        )"
	KVMVMNAME="${KVMVMNAME//[^0-9a-zA-Z-]}" # remove risky characters
    fi
    
    # Note: The default multicast IP address used to be 230.0.0.1, because that was the
    # address used in the multicast socket networking example in the qemu man page.  Now
    # after looking at https://tools.ietf.org/html/rfc2365, https://tools.ietf.org/html/rfc5771 and
    # and http://stackoverflow.com/questions/236231/how-do-i-choose-a-multicast-address-for-my-applications-use
    # it seems something from 239.255.0.0/16 is a more correct choice, because 230.0.0.1 is in a
    # "RESERVED" range of addresses.  So now the default is 239.255.10.10.

    # Note, to prevent this multicast address from leaving the machine hosting the KVM virtual machines,
    # route the packets to localhost using "sudo ifconfig lo localhost" and
    # "route add -net 239.255.10.0 netmask 255.255.255.0 dev lo".  It seems this should be done
    # before the KVMs are booted, because (sometimes) the route command can stop existing KVMs using the
    # multicast IP addresses from exchanging network packets.

    build-cmd-line() # a function, not a step
    {
        ## Putting all non-wakame nodes on 10.0.3.0/24 so Wakame instances can be accessed at 10.0.2.0/24
	: ${EXTRAHOSTFWD:=} # set -u workaround
	cat <<EOF
	    $KVMBIN

	    -m $KVMMEM
	    -smp 2
	    -name $KVMVMNAME

	    -monitor telnet:127.0.0.1:$MONPORT,server,nowait
	    -no-kvm-pit-reinjection
	    -vnc 127.0.0.1:$VNCPORT
	    -serial telnet:127.0.0.1:$SERPORT,server,nowait
	    -drive file=$IMAGEFILENAME,id=vol-tu3y7qj4-drive,if=none,serial=vol-tu3y7qj4,cache=none,aio=native
	    -device virtio-blk-pci,id=vol-tu3y7qj4,drive=vol-tu3y7qj4-drive,bootindex=0,bus=pci.0,addr=0x4

	    -net nic,vlan=0,macaddr=52:54:00:65:28:dd,model=virtio,addr=10
	    -net user,net=10.0.3.0/24,vlan=0,hostfwd=tcp::$SSHPORT-:22$EXTRAHOSTFWD$hostfwdrel

            $mcastnet
	    $bridgetapnet
EOF
    }

    portcollision()
    {
	erroutput="$(cat "$DATADIR/runinfo/kvm.stderr")"
	for i in "could not set up host forwarding rule" \
		     "Failed to bind socket" \
		     "socket bind failed"
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
		# Using /dev/null in the next line so that ssh will exit when used to call
		# this script.  Otherwise, the open stdout and stderr will keep ssh connected.
		setsid "$ORGCODEDIR/monitor-process.sh" runinfo/kvm "${kpat[@]}" 1>/dev/null 2>&1 &
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
    ) ; $iferr_exit
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
    ) ; $iferr_exit
)
