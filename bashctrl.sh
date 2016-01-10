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

helper-function-definitions()
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
    exit_if_failed=prev_cmd_failed
}
    
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
    : ${starting_step:=just_remember_step_title}
    : ${skip_step_if_already_done:=output_title_and_skipinfo_at_outline_depth}

    : ${starting_group:=default_group_header}
    : ${skip_group_if_unnecessary:=default_skip_group2}

    export BASHCTRL_DEPTH=1
    just_remember_step_title()
    {
	# This hook appears at the start of a step, so defining the
	# step title here make the title appear at the start of the
	# step in the source code.  However, during execution it is
	# desirable to display other information that is not available
	# yet along with the title.  Therefore this step only
	# remembers the title in a variable.  It can assume that the
	# hook for $skip_step_if_already_done will output the title,
	# because that hook is required and all code between this hook
	# and the "skip_step" hook must execute without side effects
	# or terminating errors.
	[ "$*" = "" ] && return 0
	step_title="$*"
    }
    export -f just_remember_step_title

    output_title_and_skipinfo_at_outline_depth()
    {
	# This hook implements the step skipping functionality plus
	# adds minimal output.  It reads the error code from the
	# checking code and if it shows success (rc==0), then it
	# assumes that the step has already been done and that it can
	# be skipped.  It assumes $step_title has already been set.
	# TODO: put try to put in useful simple info when $step_title
	# is not set.  It assumes $BASHCTRL_DEPTH is correct.
	if (($? == 0)); then
	    outline_header_at_depth "$BASHCTRL_DEPTH"
	    echo "Skipping step: $step_title"
	    step_title=""
	    exit 0 # i.e. skip (without error) to end of process/step
	else
	    echo
	    outline_header_at_depth "$BASHCTRL_DEPTH"
	    echo "DOING STEP: $step_title"
	    step_title=""
	fi
    }
    export -f output_title_and_skipinfo_at_outline_depth

    default_group_header()
    {
	export group_title="$*"
	outline_header_at_depth "$BASHCTRL_DEPTH"
	(( BASHCTRL_DEPTH++ ))
	echo "$group_title"
    }
    export -f default_group_header
    
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
		helper-function-definitions
		default-definitions
		echo "* An in-order list of steps with bash nesting info.  No attempt to show hierarchy:"
		dump1-definitions
		;;
	    status-all | status)
		choosecmd "$1"
		helper-function-definitions
		default-definitions
		status-definitions
		echo "* Status of all steps in dependency hierarchy with no pruning"
		;;
	    status1)
		choosecmd "$1"
		export title_glob="$2" ; shift
		helper-function-definitions
		default-definitions
		status-definitions
		filter-definitions
		;;
	    [d]o)
		choosecmd "$1"
		helper-function-definitions
		default-definitions
		;;
	    [d]o1)
		choosecmd "$1"
		export title_glob="$2" ; shift
		helper-function-definitions
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
