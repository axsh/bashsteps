#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}
export -f reportfailed

# initialize variables that cause trouble when this script wraps a script that
# uses set -u
: ${starting_step_extra_hook:=""}
export starting_step_extra_hook

source_lineinfo_collect()
{
    if [ "$#" = "0" ]; then # this works even if set -u is enabled
	index=2
    else
	index="$1"
    fi
    oifs="$IFS"
    IFS=,
#    echo ------------------------------
#    echo FUNCNAME="${FUNCNAME[*]}"
#    echo BASH_SOURCE="${BASH_SOURCE[*]}"
#    echo BASH_LINENO="${BASH_LINENO[*]}"
#    echo ==============================
    #    source_lineinfo="::::::::::${BASH_LINENO[1]}:${BASH_SOURCE[index]}:${FUNCNAME[2]}"
    set +u # Give up on set -u if this code path is taken
    apath="${BASH_SOURCE[index]}"
    nolinks="$(readlink -f "$apath")" # necessary because github does not follow symbolic links
    fullsource="$nolinks::${BASH_LINENO[1]}"
    echo "$fullsource" >>/tmp/yy2
    
    if [ "$reldir" != "" ] ; then
	usedsource="${fullsource#${reldir%/}}"
	[ "$fullsource" != "$usedsource" ] && usedsource=".$usedsource"
    else
	usedsource="$fullsource"
    fi
    source_lineinfo="$(printf "%10s[[%s][%s]]\n" "" "$usedsource" "${fullsource##*/}")"
    IFS="$oifs"
}
source_lineinfo_output()
{
    echo ":: $source_lineinfo"
}
export -f source_lineinfo_collect
export -f source_lineinfo_output

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

    # for consistency, start to use the variable form for everything
    : ${prev_cmd_failed:='eval [ $? = 0 ] || exit 255'}
    export prev_cmd_failed
}
    
null-definitions()
{
    # The simplest bashsteps hook possible is ":", which just lets
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


# This set of definitions is probably the simplest where all four hooks
# serves a purpose.
optimized-actions-with-terse-output-definitions()
{
    # This is a complete set of hook definitions that lets the script
    # run through and complete all not-yet-done actions.  For each
    # individual steps, it lets the check part run, and if the checks
    # succeed, it skips the action portion.  A status line for each
    # step is sent to stdout after the checks and before the actions.
    # The status line is indented in org-mode style to reflect the
    # outline depth computed by the group hooks.  At the start of each
    # group, a status line is immediately sent to stdout.  Then the
    # check for the group (if any) are done and if the check succeed,
    # the rest of the group (and any groups or steps inside) are
    # completely skipped.  Therefore, for some steps it is possible
    # that none of the hooks are touched.

    : ${starting_step:=just_remember_step_title}  # OPTIONAL
    : ${skip_step_if_already_done:=output_title_and_skipinfo_at_outline_depth} # REQUIRED

    : ${starting_group:=remember_and_output_group_title_in_outline} # REQUIRED
    : ${skip_group_if_unnecessary:=maybe_skip_group_and_output_if_skipping} # OPTIONAL

    export BASHCTRL_DEPTH=1
    export BASHCTRL_INDEX=1
    just_remember_step_title() # for $starting_step
    {
	# This hook appears at the start of a step, so defining the
	# step title here lets the title appear at the start of the
	# step in the source code.  However, during execution it is
	# desirable to display other information that is not available
	# yet along with the title.  Therefore this step only
	# remembers the title in a variable.  It can assume that the
	# hook for $skip_step_if_already_done will output the title,
	# because that hook is required and all code between this hook
	# and the "skip_step" hook must execute without side effects
	# or terminating errors.
	source_lineinfo_collect
	parents=""
	[[ "$BASHCTRL_INDEX" == *.* ]] && parents="${BASHCTRL_INDEX%.*}".
	{ exec 2>/dev/null ; read nextcount <&78 || nextcount=1000 ; } 2>/dev/null
	leafindex="${BASHCTRL_INDEX##*.}"
	BASHCTRL_INDEX="$parents$nextcount"

	export step_title="$BASHCTRL_INDEX-$*"
	$starting_step_extra_hook
    }
    export -f just_remember_step_title

    output_title_and_skipinfo_at_outline_depth() # for $skip_step_if_already_done
    {
	# This hook implements the step skipping functionality plus
	# adds minimal output.  It reads the error code from the
	# checking code and if it shows success (rc==0), then it
	# assumes that the step has already been done and that it can
	# be skipped.  It assumes $step_title has already been set.
	# TODO: try to put in useful simple info when $step_title
	# is not set.  It assumes $BASHCTRL_DEPTH is correct.
	if (($? == 0)); then
	    ( set +x
	      outline_header_at_depth "$BASHCTRL_DEPTH"
	    )
	    echo "Skipping step: $step_title"
	    source_lineinfo_output
	    step_title=""
	    exit 0 # i.e. skip (without error) to end of process/step
	else
	    ( set +x
	      echo
	      outline_header_at_depth "$BASHCTRL_DEPTH"
	    )
	    echo "DOING STEP: $step_title"
	    source_lineinfo_output
	    step_title=""
	    $verboseoption && set -x
	fi
    }
    export -f output_title_and_skipinfo_at_outline_depth

    remember_and_output_group_title_in_outline() # for $starting_group
    {
	# This hook remembers the group title in a bash
	# variable and outputs it immediately to the outline log.  The
	# hook is required for groups, and the other group hooks are
	# optional so here is the only (straightforward) place to do
	# such output.  Also, since this hook is required for all
	# groups, here is a reliable place to update the value of
	# $BASHCTRL_DEPTH.
	parents=""
	[[ "$BASHCTRL_INDEX" == *.* ]] && parents="${BASHCTRL_INDEX%.*}".
	{ exec 2>/dev/null ; read nextcount <&78 || nextcount=1000 ; } 2>/dev/null
	BASHCTRL_INDEX="$parents$nextcount.yyy"
	exec 78< <(seq 1 1000)

	export group_title="${BASHCTRL_INDEX%.yyy}.0-$*"
	( set +x
	  outline_header_at_depth "$BASHCTRL_DEPTH"
	  echo "$group_title :::" )
	(( BASHCTRL_DEPTH++ ))
	source_lineinfo_collect
	source_lineinfo_output
    }
    export -f remember_and_output_group_title_in_outline

    # initialize top level index
    BASHCTRL_INDEX="1"
    exec 78< <(seq 1 1000)
    
    maybe_skip_group_and_output_if_skipping() # for $skip_group_if_unnecessary
    {
	# If the preceding bash statement returns success (rc==0),
	# this hook skips the whole group, including the checks of any
	# of the steps.  This makes sense when executing. (When
	# running the script to collect as much status information as
	# possible, it makes more sense to execute all the steps in
	# the group.)
	if (($? == 0)); then
	    echo "      Skipping group: $group_title"
	    group_title=""
	    exit 0
	else
	    echo ; echo "      DOING GROUP: $group_title"
	    group_title=""
	fi
    }
    export -f maybe_skip_group_and_output_if_skipping

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

outputlineinfo()
{
    echo "${BASH_SOURCE[*]}",,,sss-"${#BASH_SOURCE[*]}"
    echo "$(caller 0),,,ccc 0"
    echo "$(caller 1),,,ccc 1"
    echo "$(caller 2),,,ccc 2"
    echo "${BASH_LINENO[*]}",,,LLL-"${#BASH_LINENO[*]}"
    echo "${FUNCNAME[*]}",,,LLL-"${#FUNCNAME[*]}"
    echo "${LINENO}<<-LINENO"
}
export -f outputlineinfo

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
exec 88< <(seq 1 100) # debug counter
quick-definitions()
{
    starting_step=immediately_output_step_title_in_outline
    starting_group=remember_and_output_group_title_in_outline
    skip_step_if_already_done='echo BUG; exit 0'
    skip_group_if_unnecessary=':'
    export starting_step
    export starting_group
    export skip_step_if_already_done
    export skip_group_if_already_done

    immediately_output_step_title_in_outline() # for $starting_step
    {
	# This hook remembers the step title in a bash variable and
	# outputs it immediately to the outline log.  It then
	# immediately exist, so nothing in the step is executed.  For
	# this to work as intended, every step must have a
	# $starting_step hook.
	parents=""
	[[ "$BASHCTRL_INDEX" == *.* ]] && parents="${BASHCTRL_INDEX%.*}".
	{ exec 2>/dev/null ; read nextcount <&78 || nextcount=1000 ; } 2>/dev/null
	leafindex="${BASHCTRL_INDEX##*.}"
	BASHCTRL_INDEX="$parents$nextcount"

	export step_title="$BASHCTRL_INDEX-$*"
	( set +x
	  outline_header_at_depth "$BASHCTRL_DEPTH"
	  echo "$step_title" )
	read debugcount <&88
	outputlineinfo
	(( debugcount > 8 )) && exit 0
	exit 0 # Move on to next step!
    }
    export -f immediately_output_step_title_in_outline

    # create a counter (up to 1000!) for all subprocesses to share.
    # (seems to be killed automatically by SIGHUP)
}

status-definitions()
{
    # make status safer when used with scripts using old style
    export skip_rest_if_already_done=status_skip_step

    skip_step_if_already_done=status_skip_step

    if $verboseoption; then
	starting_step_extra_hook=extra_for_status
	export starting_step_extra_hook
	
	extra_for_status()
	{
	    (
		set +x
		outline_header_at_depth "$BASHCTRL_DEPTH"
		echo "vvvvvvvvvvvvvvvvv"
	    )
	    set -x
	}
	export -f extra_for_status
    fi

    export skip_whole_tree=''
    skip_group_if_unnecessary='eval (( $? == 0 )) && skip_whole_tree=,skippable'
    
    status_skip_step() # for skip_step_if_already_done
    {
	rc="$?"
	set +x
	outline_header_at_depth "$BASHCTRL_DEPTH"
	echo -n "$step_title"
	if (($rc == 0)); then
	    echo " (DONE$skip_whole_tree)"
	    step_title=""
	else
	    echo " (not done$skip_whole_tree)"
	    step_title=""
	fi
	source_lineinfo_output
	exit 0 # Always, because we are just checking status
    }
    export -f status_skip_step

    # create a counter (up to 1000!) for all subprocesses to share.
    # (seems to be killed automatically by SIGHUP)
}

filter-definitions()
{
    starting_step=filter_header_step
    starting_group='filter_header_group'
    filter_header_step()
    {
	parents=""
	[[ "$BASHCTRL_INDEX" == *.* ]] && parents="${BASHCTRL_INDEX%.*}".
	{ exec 2>/dev/null ; read nextcount <&78 || nextcount=1000 ; } 2>/dev/null
	leafindex="${BASHCTRL_INDEX##*.}"
	BASHCTRL_INDEX="$parents$nextcount"

	export step_title="$BASHCTRL_INDEX-$*"
#	echo "$step_title" != $title_glob ,,,,,
	if [[ "$step_title" != $title_glob ]]; then
	    step_title=""
	    exit 0
	fi
	$starting_step_extra_hook
    }
    export -f filter_header_step

    filter_header_group()
    {
	parents=""
	[[ "$BASHCTRL_INDEX" == *.* ]] && parents="${BASHCTRL_INDEX%.*}".
	{ exec 2>/dev/null ; read nextcount <&78 || nextcount=1000 ; } 2>/dev/null
	BASHCTRL_INDEX="$parents$nextcount.yyy"
	exec 78< <(seq 1 1000)
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
	$verboseoption && set -x
    }
    export -f do1_skip_step
}

thecmd=""
choosecmd()
{
    [ "$thecmd" = "" ] || reportfailed "Cannot override $thecmd with $1"
    thecmd="$1"
}

# status1 and do1 now take the pattern appended to the command
# to make parsing easier. For example:
#   status1-yum   -> give status of all titles matching *yum*.
#   'do1-*Install'  -> do all steps with titles that start with "Install"
glob_heuristics()
{
    [ "$1" = "" ] && reportfailed "A pattern must be appended to the command"
    if [[ "$1" == *\** ]]; then
	# if it already has a glob character, return unchanged
	echo "$1"
    else
	# else wrap so that the fixed string can match anywhere in the title
	echo "*$1*"
    fi
}


markdown_convert()
{
    pat=']['
    while true; do
	pref=""
	## read org-mode **... prefixes and convert to markdown headings
	while IFS= read -n 1 c; do
	    if [ "$c" = "*" ]; then
		pref="#$pref"
	    else
		pref="$c$pref"
		break
	    fi
	done
	IFS= read -r ln || break
	## link line is of the form:  ":  [[file::line#][label::line#]]"
	if [[ "$ln" == *$pat* ]]; then
	    IFS='[]: ' read colon1 emptya emptyb filepath emptyc n1 emptyd label emptye n2 rest <<<"$ln"
	    [ "$emptya$emptyb$emptyc$emptyd$emptye" != "" ] && echo "bug"
	    echo "[$label]($filepath#L$n1)"
	else
	    printf "%s\n" "$pref$ln"
	fi
    done
}

orglink_convert()
{
    saveline="XXX"
    pat=']['
    while true; do
	pref=""
	## read org-mode **... prefixes and convert to markdown headings
	while IFS= read -n 1 c; do
	    if [ "$c" = "*" ]; then
		pref="*$pref"
	    else
		pref="$pref$c"
		break
	    fi
	done
	IFS= read -r ln || break
#	echo ">>>$ln"
	## link line is of the form:  ":  [[file::line#][label::line#]]"
	if [[ "$ln" == *$pat* ]]; then
	    IFS='[]: ' read colon1 emptya emptyb filepath emptyc n1 emptyd label emptye n2 rest <<<"$ln"
	    [ "$emptya$emptyb$emptyc$emptyd$emptye" != "" ] && echo "bug"
	    IFS=':' read mid rest <<<"$saveline"
	    IFS=' ' read index rest2 <<<"$rest"
	    echo "$savepref $mid[[$filepath::$n1][$index]] $rest2"
	    saveline="XXX"
	else
	    savepref="$pref"
	    saveline="$(printf "%s\n" "$ln")"
	fi
    done
}

make_sure_filepath_is_in_repository()
{
    out="$(git ls-files "$filepath")"
    [ "$out" != "" ] && return 0

    # try to find the same file somewhere in the repository
    orgmd5="$(md5sum "$filepath")"
    orgmd5="${orgmd5:0:32}"

    alternatives="$(find ./  -name "${filepath##*/}")"
    while IFS= read -r ln; do
	out="$(git ls-files "$ln")"
	[ "$out" = "" ] && continue
	md5="$(md5sum "$ln")"
	[ "$orgmd5" != "${md5:0:32}" ] && continue

	filepath="$ln" # found a match visible on github
	break
    done <<<"$alternatives"
}

mdlink_convert() # almost exact copy of orglink_convert()
{
    saveline="XXX"
    pat=']['
    while true; do
	pref=""
	## read org-mode **... prefixes and convert to markdown headings
	while IFS= read -n 1 c; do
	    if [ "$c" = "*" ]; then
		pref="&#42;$pref"   # &#42; for html asterisk
	    else
		pref="$pref$c"
		break
	    fi
	done
	IFS= read -r ln || break
	## link line is of the form:  ":  [[file::line#][label::line#]]"
	if [[ "$ln" == *$pat* ]]; then
	    IFS='[]: ' read colon1 emptya emptyb filepath emptyc n1 emptyd label emptye n2 rest <<<"$ln"
	    make_sure_filepath_is_in_repository
	    [ "$emptya$emptyb$emptyc$emptyd$emptye" != "" ] && echo "bug"
	    IFS=':' read mid rest <<<"$saveline"
	    IFS=' ' read index rest2 <<<"$rest"
	    frompat='//' ; topat='/ /'
	    rest2="${rest2//$frompat/$topat}" # make sure urls in headings don't mess up markdown
	    htmllink_part="<a href=\"$rel_md_link/$filepath#L$n1\">$index $rest2</a>"
	    markdown_output="<code>$savepref $mid${htmllink_part}</code><br>"
	    # use non-breaking spaces so indentation will look OK
	    # (Maybe github strips them out?  Maybe <code> strips them out?  Not sure.)
	    subs_nbsp="${markdown_output// /&nbsp;}"
	    final_markdown="${subs_nbsp//<a&nbsp;/<a }" # but not the space inside the anchor tag!
	    echo "$final_markdown"
	    saveline="XXX"
	else
	    savepref="$pref"
	    saveline="$(printf "%s\n" "$ln")"
	fi
    done
}

indent_convert()
{
    while true; do
	pref=""
	mid=""
	## read org-mode **... prefixes and convert to markdown headings
	while IFS= read -n 1 c; do
	    if [ "$c" = "*" ]; then
		pref="*$pref"
		[ "$pref" = '*' ] || [ "$pref" = '**' ] || mid="$mid  --  "
	    else
		if [ "$pref" = "" ]; then
		    # it is not an org-mode line, probably a link line
		    IFS= read -r rest
		    printf "%s%s\n" "$c" "$rest"
		    continue
		fi
		pref="$pref$c"
		break
	    fi
	done
	IFS= IFS=' :-' read -r xx index ln || break
	printf "%-7s %s %s %s\n" "$pref" "$mid" ": $index" "$ln"
    done
}

cmdline=( )
bashxoption=""
export verboseoption=false
export markdownoption=false
export orglinkoption=false
export mdlinkoption=false
export linesoption=false
export indentoption=false
export reldir="$(pwd)"
parse-parameters()
{
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    nulldefs | passthru)
		choosecmd "$1"
		;;
	    in-order | debug)
		choosecmd "$1"
		;;
	    quick)
		choosecmd "$1"
		;;
	    status-all | status | check)
		choosecmd "$1"
		;;
	    status1-*)
		choosecmd "${1%%-*}"
		export title_glob="$(glob_heuristics "${1#status1-}")"
		;;
	    check1-*)
		choosecmd "${1%%-*}"
		export title_glob="$(glob_heuristics "${1#check1-}")"
		;;
	    [d]o)
		choosecmd "$1"
		;;
	    [d]o1-*)
		choosecmd "${1%%-*}"
		export title_glob="$(glob_heuristics "${1#do1-}")"
		;;
	    bashx)
		bashxoption='bash -x'
		;;
	    verbose)
		verboseoption=true
		;;
	    old-markdown)
		markdownoption=true
		;;
	    orglink*)
		linesoption=true
		orglinkoption=true
		;;
	    mdlink*)
		linesoption=true
		mdlinkoption=true
		;;
	    orgmode | org-mode)
		# This works pretty good:  ./bashctrl.sh ./buildscript.sh status orgmode >mapname.org
		linesoption=true  # output original file/line# info
		indentoption=true # pipe through indent_convert()
		orglinkoption=true # pipe through orglink_convert()
		;;
	    markdown)
		[ -d .git ] || \
		    reportfailed "markdown option should only be used at the root of a git repository"
		# This works OK:  ./bashctrl.sh ./buildscript.sh status markdown >mapname.md
		linesoption=true  # output original file/line# info
		indentoption=true # pipe through indent_convert()
		mdlinkoption=true # pipe through mdlink_convert()
		;;
	    abs* | abspath)
		reldir=""
		;;
	    lines | links)
		linesoption=true
		;;
	    indent)
		indentoption=true
		;;
	    *)
		cmdline=( "${cmdline[@]}" "$1" )
		;;
	esac
	shift
    done
}

theheading=""
bashctrl-main()
{
    parse-parameters "$@"
    case "$thecmd" in
	nulldefs | passthru)
	    null-definitions
	    ;;
	in-order | debug)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    theheading="* An in-order list of steps with bash nesting info.  No attempt to show hierarchy:"
	    dump1-definitions
	    ;;
	quick)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    theheading="* An in-order list of steps with bash nesting info.  No evaluation of status checks."
	    quick-definitions
	    ;;
	status-all | status | check)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    status-definitions
	    theheading="* Status of all steps in dependency hierarchy with no pruning"
	    ;;
	status1 | check1)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    status-definitions
	    filter-definitions
	    ;;
	[d]o)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    ;;
	[d]o1)
	    helper-function-definitions
	    optimized-actions-with-terse-output-definitions
	    do1-definitions
	    filter-definitions
	    ;;
	*)
	    reportfailed "No command chosen"
	    ;;
    esac

    absolute_path()
    {
	if [[ "$1" == /* ]]; then # already absolute path
	    echo "$1"
	else  # convert relative to absolute path
	    echo "$(pwd)/${1#./}"
	fi
    }

    # Make into full path so BASH_SOURCE will have full paths.
    # Keep symbolic links in the path so the implicit DATADIR setting
    # will still work.
    firsttoken="${cmdline[0]}"
    cmdline[0]="$(absolute_path "$firsttoken")"

    if $linesoption; then
	# if $BASH_SOURCE is referenced from a function that was exported
	# from a parent shell, it returns (or will soon return) and empty
	# string.  The following is a workaround to redefine the function
	# in the current process.
	export -pf >"/tmp/export-for-bashctrl-$$"
	export BASH_ENV="/tmp/export-for-bashctrl-$$"
    else
	source_lineinfo_collect() { : ; }
	source_lineinfo_output() { : ; }
    fi

    # basic formatting is, e.g.: *** : 1.1-Make t-fff (not done)
    # so main delimiters are : and -
    # IFS=' :-' read orgpref index rest
    # links formatting adds: ::   [[./examples/new/new-duped-substep.sh::17][new-duped-substep.sh::17]]

    if $markdownoption; then
	$bashxoption "${cmdline[@]}" | markdown_convert
    elif $indentoption && $orglinkoption; then
	echo "$theheading"
	$bashxoption "${cmdline[@]}" | indent_convert | orglink_convert
    elif $indentoption && $mdlinkoption; then
	commithash="$(git log -1 --pretty=format:%H)"
	commitlink="../../tree/$commithash/"
	export rel_md_link="../../blob/$commithash"
	anchor="<a href=\"$commitlink\">$commitlink</a>"
	# The following **does not** quite work, because the map file is
	# in the commit *after* $commitlink.
	echo "The map was made from this tree: $anchor"
	echo "<br>"
	echo "<code>$theheading</code><br>"
	$bashxoption "${cmdline[@]}" | indent_convert | mdlink_convert
    elif $indentoption; then
	$bashxoption "${cmdline[@]}" | indent_convert
    elif $orglinkoption; then
	$bashxoption "${cmdline[@]}" | orglink_convert
    elif $mdlinkoption; then
	$bashxoption "${cmdline[@]}" | mdlink_convert
    else
	echo "$theheading"
	$bashxoption "${cmdline[@]}"
    fi
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
	BASHCTRL_INDEX
	BASHCTRL_DEPTH
	title_glob
        starting_step_extra_hook
        skip_whole_tree
        verboseoption
"

export_funtions_for_remote="
 ${export_funtions_for_remote:=}
        outline_header_at_depth
        source_lineinfo_output
        source_lineinfo_collect
	starting_step_extra_hook
	skip_whole_tree
	reldir
	title_glob
"

export export_variables_for_remote
export export_funtions_for_remote

bashctrl-main "$@"
