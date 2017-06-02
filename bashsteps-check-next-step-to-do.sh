#!/bin/bash


# The next three will override in bashsteps scripts that use the varialbe forms
# of the hooks, i.e. "$iferr_exit" instead of "iferr_exit" or "prev_cmd_failed".

export iferr_continue    ; : ${iferr_continue:="checknext_iferr_continue"}
export iferr_exit        ; : ${iferr_exit:="checknext_iferr_exit"}
export iferr_killpg      ; : ${iferr_killpg:="checknext_iferr_killpg"}
export prev_cmd_failed="checknext_iferr_exit"

checknext_iferr_continue()
{
    # no error messages for this case, and also exit, not continue
    rc="$?"
    [ "$rc" = "0" ] && return 0
    exit 252
}

checknext_iferr_exit()
{
    # no error messages for this case
    rc="$?"
    [ "$rc" = "0" ] && return 0
    exit 252
}

checknext_iferr_killpg()
{
    # no error messages for this case
    rc="$?"
    [ "$rc" = "0" ] && return 0
    exit 252
}

export -f checknext_iferr_continue
export -f checknext_iferr_exit
export -f checknext_iferr_killpg

setup_checknext_framework()
{
    # the new framework:
    : ${starting_step:=checknext_set_title}
    : ${starting_group:=checknext_set_title}
    : ${skip_step_if_already_done:=checknext_skip_step}
    : ${skip_group_if_unnecessary:=checknext_skip_group}
    export starting_step
    export starting_group
    export skip_step_if_already_done
    export skip_group_if_unnecessary

    checknext_set_title()
    {
	[ "$*" != "" ] && step_title="$*"
    }
    export -f checknext_set_title

    checknext_skip_step()
    {
        rc="$?"
	[ "$debugoutput" != "" ] && echo "checking step: $step_title"
	if (($rc == 0)); then
	    exit 0 # exit the process for the step, but keep going
	else
	    echo "Next step to do: $step_title"
	    exit 252 # not really an error, just a way to exit all groups that wrap this step
	fi
    }
    export -f checknext_skip_step

    checknext_skip_group()
    {
        rc="$?"
	[ "$debugoutput" != "" ] && echo "checking group: $step_title"
	if (($rc == 0)); then
	    exit 0
	fi
    }
    export -f checknext_skip_group
}


# If one bashsteps script tries to call another remotely,
# it should do its best to make sure these functions and
# variables are copied to the remote environment.
# If a variable's value is a function name, that function
# should also be automatically copied.

export_variables_for_remote="
 ${export_variables_for_remote:=}
	starting_group
	starting_step
	skip_step_if_already_done
	skip_group_if_unnecessary
	prev_cmd_failed
	iferr_exit
	iferr_continue
        debugoutput
"

export_funtions_for_remote="
 ${export_funtions_for_remote:=}
"

export export_variables_for_remote
export export_funtions_for_remote

thescript="$1"
shift
[ -x "$thescript" ] || {
    echo "Script not found ($thescript)" 1>&2
    exit 1
}

setup_checknext_framework

if [ "${show_checks:=}" != "" ] ; then
    export debugoutput=true
else
    export debugoutput=""
fi

"$thescript" "$@"  # Run the script with the passed in parameters unchanged
rc="$?"

[ "$rc" = "0" ] && exit 1  # there were no steps to do, so "fail"
exit 0 # there is a next step to do, so "success" in finding it
