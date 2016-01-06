#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}
export -f reportfailed

# The script called by this should have the following pattern:

# reused-dependent()
# {
#    (
#       ......
#    ) ; $finished_step
# }

#  (
     ## sequential dependent
#  ) ; $finished_step

#  reused-sequential-dependent

#  (
#      reset() { reset code; }
#      (
          ## nexted dependant
#      ) ; $finished_step
#      reused-nested-dependant
#      $starting_checks "step name"
#      script-to-check-if-done
#      $skip_rest_if_already_done; set -e
#      script-to-do-the-step
#  ) ; $finished_step

# simple but ugly

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

    # old framework:
    : ${starting_dependents:=default_header2}
    : ${starting_checks:=default_header2}
    : ${skip_rest_if_already_done:=default_skip_step} # exit (sub)process if return code is 0
    export starting_dependents
    export starting_checks
    export skip_rest_if_already_done

    # new framework:
    : ${starting_step:=default_header2}
    : ${starting_group:=default_set_title} # TODO:
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
    starting_dependents=dump1_header
    starting_checks=dump1_header
    skip_rest_if_already_done='exit 0'
    export starting_dependents
    export starting_checks
    export skip_rest_if_already_done

    export BASH_SUBSHELL_BASE=$BASH_SUBSHELL
    dump1_header()
    {
	[ "$*" = "" ] && return 0
	step_title="$*"
	echo "** : $step_title  (\$SHLVL=$SHLVL, \$BASH_SUBSHELL=$BASH_SUBSHELL)"
    }
    export -f dump1_header
}

dump-definitions()
{
    starting_checks=dump1_header
    skip_rest_if_already_done='exit 0'

    export BASH_SUBSHELL_BASE=$BASH_SUBSHELL
    dump1_header()
    {
	step_title="$*"
	for (( i = BASH_SUBSHELL_BASE; i <= BASH_SUBSHELL; i++ )); do
	    echo -n "*"
	done
	echo " : $step_title"
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
		echo "* An in-order list of steps"
		dump1-definitions
		;;
	    dump)
		choosecmd "$1"
		default-definitions
		dump-definitions
		echo "* Step dependency hierarchy with no pruning"
		usetac=true
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
