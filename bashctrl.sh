#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}
export -f reportfailed


# The following variables are used to set bashsteps hooks, which are
# used to control and debug bash scripts that use the bashsteps
# framework:
export starting_step
export starting_group
export skip_step_if_already_done
export skip_group_if_unnecessary

null-definitions()
{
    # The simplest bashsteps hookpossible is ":", which just let
    # control passthru the hooks without any effect. ("" will not work
    # because hooks can be invoked with parameter, and the null
    # operation must ignore the parameters.)  In general, a script
    # starting from a clean environment should run correctly with null
    # definitions, because running the script will traverse all steps,
    # and the steps should already be ordered so that steps that
    # require preconditions are always run after steps that establish
    # the same preconditions.
    : ${starting_step:=":"}
    : ${starting_group:=":"}
    : ${skip_step_if_already_done:=":"}
    : ${skip_group_if_unnecessary:=":"}
}


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
    : ${starting_group:=default_group_header}
    : ${skip_step_if_already_done:=default_skip_step2}
    : ${skip_group_if_unnecessary:=default_skip_group2}

    export BASHCTRL_DEPTH=1
    default_header2()
    {
	[ "$*" = "" ] && return 0
	step_title="$*"
    }
    export -f default_header2

    default_group_header()
    {
	export group_title="$*"
	outline_header_at_depth "$BASHCTRL_DEPTH"
	(( BASHCTRL_DEPTH++ ))
	echo "$group_title"
    }
    export -f default_group_header
    
    default_skip_step2()
    {
	if (($? == 0)); then
	    outline_header_at_depth "$BASHCTRL_DEPTH"
	    echo "Skipping step: $step_title"
	    step_title=""
	    exit 0
	else
	    echo
	    outline_header_at_depth "$BASHCTRL_DEPTH"
	    echo "DOING STEP: $step_title"
	    step_title=""
	fi
    }
    export -f default_skip_step2

    default_skip_group2()
    {
	if (($? == 0)); then
	    echo "      Skipping group: $group_title"
	    group_title=""
	    exit 0
	else
	    echo ; echo "      DOING GROUP: $group_title"
	    group_title=""
	fi
    }
    export -f default_skip_group2

    finished_step=prev_cmd_failed
}

outline_header_at_depth()
{
    depth="$1"
    for (( i = 0; i <= depth; i++ )); do
	echo -n "*"
    done
    echo -n " : "
}
export -f outline_header_at_depth

dump1-definitions()
{
    starting_step=dump1_header
    starting_group=dump1_header
    skip_step_if_already_done='exit 0'
    skip_group_if_unnecessary=':'
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

    export skip_whole_tree=''
    skip_group_if_unnecessary='eval (( $? == 0 )) && skip_whole_tree=,skippable'
    
    status_skip_step()
    {
	rc="$?"
	outline_header_at_depth "$BASHCTRL_DEPTH"
	echo -n "$step_title"
	if (($rc == 0)); then
	    echo " (DONE$skip_whole_tree)"
	    step_title=""
	else
	    echo " (not done$skip_whole_tree)"
	    step_title=""
	fi
	exit 0 # Always, because we are just checking status
    }
    export -f status_skip_step
}

filter-definitions()
{
    starting_step=filter_header_step
    starting_group=':'
    filter_header_step()
    {
	step_title="$*"
	if [[ "$step_title" != $title_glob ]]; then
	    step_title=""
	    exit 0
	fi
    }
    export -f filter_header_step

    filter_header_group()
    {
	group_title="$*"
	if [[ "$group_title" != $title_glob ]]; then
	    group_title=""
	    exit 0
	fi
    }
    export -f filter_header_group
}

do1-definitions()
{
    skip_step_if_already_done=do1_skip_step
    starting_group=':'
    skip_group_if_unnecessary=':'

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
	    nulldefs | passthru)
		choosecmd "$1"
		null-definitions
		;;
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
