#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}
export -f reportfailed

default-definitions()
{
    prev_cmd_failed()
    {
	# this is needed because '( cmd1 ; cmd2 ; set -e ; cmd3 ; cmd4 ) || reportfailed'
	# does not work because the || disables set -e, even inside the subshell!
	# see http://unix.stackexchange.com/questions/65532/why-does-set-e-not-work-inside
	# A workaround is to do  '( cmd1 ; cmd2 ; set -e ; cmd3 ; cmd4 ) ; prev_cmd_failed'
	(($? == 0)) || reportfailed "$*"
    }
    export -f prev_cmd_failed

    : ${starting_step:=default_header2}
    : ${starting_group:=default_group_header} # TODO:
    : ${skip_step_if_already_done:=default_skip_step}
    : ${skip_group_if_unnecessary:=default_skip_group}
    export starting_step
    export starting_group
    export skip_step_if_already_done
    export skip_group_if_unnecessary

    export BASHCTRL_DEPTH=0
    export PREV_SHLVL="$SHLVL"
    export PREV_BASH_SUBSHELL="$BASH_SUBSHELL"
    default_header2()
    {
	[ "$*" = "" ] && return 0
	step_title="$*"
	if [ "$PREV_SHLVL" != "$SHLVL" ] || [ "$PREV_BASH_SUBSHELL" != "$BASH_SUBSHELL" ]; then
	    (( BASHCTRL_DEPTH++ ))
	    export PREV_SHLVL="$SHLVL"
	    export PREV_BASH_SUBSHELL="$BASH_SUBSHELL"
	fi
    }
    export -f default_header2

    default_group_header()
    {
	export group_title="$*"
	(( BASHCTRL_DEPTH++ ))
	for (( i = 0; i <= BASHCTRL_DEPTH; i++ )); do
	    echo -n "*"
	done
	echo " : $group_title"
    }
    export -f default_group_header
    
    default_skip_step()
    {
	if (($? == 0)); then
	    echo "** Skipping step: $step_title"
	    step_title=""
	    exit 0
	else
	    echo ; echo "** DOING STEP: $step_title"
	    step_title=""
	fi
    }
    export -f default_skip_step

    default_skip_group()
    {
	if (($? == 0)); then
	    echo "** Skipping group: $step_title"
	    step_title=""
	    exit 0
	else
	    echo ; echo "** DOING GROUP: $step_title"
	    step_title=""
	fi
    }
    export -f default_skip_group

    finished_step=prev_cmd_failed
}

dump1-definitions()
{
    starting_step=dump1_header
    starting_group=dump1_header
    skip_step_if_already_done='exit 0'
    skip_group_if_already_done=':'
    export starting_step
    export starting_group
    export skip_step_if_already_done
    export skip_group_if_already_done

    dump1_header()
    {
	[ "$*" = "" ] && return 0
	step_title="$*"
	echo "** : $step_title  (\$SHLVL=$SHLVL, \$BASH_SUBSHELL=$BASH_SUBSHELL)"
    }
    export -f dump1_header
}

status-definitions()
{
    skip_rest_if_already_done=status_skip_step
    skip_step_if_already_done=status_skip_step

    status_skip_step()
    {
	rc="$?"
	for (( i = 0; i <= BASHCTRL_DEPTH; i++ )); do
	    echo -n "*"
	done
	echo -n " : $step_title"
	if (($rc == 0)); then
	    echo " (DONE)"
	    step_title=""
	else
	    echo " (not done)"
	    step_title=""
	fi
	exit 0 # Always, because we are just checking status
    }
    export -f status_skip_step
}

filter-definitions()
{
    starting_checks=filter_header

    export BASH_SUBSHELL_BASE=$BASH_SUBSHELL
    filter_header()
    {
	step_title="$*"
	if [[ "$step_title" != $title_glob ]]; then
	    step_title=""
	    exit 0
	fi
    }
    export -f filter_header
}

do1-definitions()
{
    skip_rest_if_already_done=do1_skip_step

    export BASH_SUBSHELL_BASE=$BASH_SUBSHELL
    do1_skip_step()
    {
	if (($? == 0)); then
	    echo "** DOING STEP AGAIN: $step_title"
	    step_title=""
	else
	    echo ; echo "** DOING STEP: $step_title"
	    step_title=""
	fi
    }
    export -f do1_skip_step
}

thecmd=""
choosecmd()
{
    [ "$thecmd" = "" ] || reportfailed "Cannot override $thecmd with $1"
    thecmd="$1"
}

cmdline=( )
usetac=false
bashxoption=""
parse-parameters()
{
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    in-order | debug)
		choosecmd "$1"
		default-definitions
		echo "* An in-order list of steps with bash nesting info.  No attempt to show hierarchy:"
		dump1-definitions
		;;
	    status-all | status)
		choosecmd "$1"
		default-definitions
		status-definitions
		echo "* Status of all steps in dependency hierarchy with no pruning"
		usetac=true
		;;
	    status1)
		choosecmd "$1"
		export title_glob="$2" ; shift
		default-definitions
		status-definitions
		filter-definitions
		;;
	    [d]o)
		choosecmd "$1"
		default-definitions
		;;
	    [d]o1)
		choosecmd "$1"
		export title_glob="$2" ; shift
		default-definitions
		do1-definitions
		filter-definitions
		;;
	    bashx)
		bashxoption='bash -x'
		;;
	    *)
		cmdline=( "${cmdline[@]}" "$1" )
		;;
	esac
	shift
    done
}

bashctrl-main()
{
    parse-parameters "$@"
    [ "$thecmd" != "" ] || reportfailed "No command chosen"
    if $usetac; then
	$bashxoption "${cmdline[@]}" | tac
    else
	$bashxoption "${cmdline[@]}"
    fi
}

bashctrl-main "$@"
