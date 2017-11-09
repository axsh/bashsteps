
### Introduction

Bashsteps is a set of hooks and bash coding requirements that help
make bash scripts safer by allowing more graceful recovery from
external failures. It does this by motivating and facilitating efforts
to (1) structure the script into meaningful steps and (2) write check
code for *all* steps.

There is more to say about this and other benefits, but probably a
better way to introduce bashsteps is first to explain the requirements
for using it.  Some of the requirements involve discipline from the
user, so knowledge about the requirements is necessary to be sucessful
with bashsteps.  Starting out this way is also a good way to emphasize
that there are only a few requriements, which is actually a key
benefit itself.

### software requirements

The first requirement is that 3 "bashsteps hook" variables be defined.
One way to define them that is minimal but still useful is to copy and
paste the following code to the start of the script.  These
particularly settings for the hooks makes the script skip any step that
has already been done.

```
: ${prev_cmd_failed:='eval [ $? == 0 ] || exit #'}
: ${starting_step:=':'}
: ${skip_step_if_already_done:='eval [ $? == 0 ] && exit #'}
```

That is it!  Other options for defining the hooks exist, which are
described elsewhere, but it is worth emphasizing that no other
software, libraries, or "plugins" are *required*.

### coding requirments/coding convensions:

The coding requirements do require some discipline from the script
writer.  Fortunately, there are only a few rules that have to be
followed.

(1) Every step must start a new process.  (Bash provides a few easy
ways to do this.  Some work inline, some split steps into separate
files.  Any are OK.)

(2) The code in the process must be split into two parts.  Let's call
them the "check" part and the "do" part.  The "check" part must appear
first in the execution flow.  The "do" part's execution must always
follow all of the check part's execution.

(3) The "check" code should be written to check if the step has
already been done.  If so, it should finish execution with a zero
return code.  It must always execute to completion.  Therefore, it
must never exit or cause fatal errors.  (This means "set -e" should
usually not be active in "check" code.)

(4) The "check" part must not change external state.  Never.  

(5) The "do" part is the code that does the step.  If it is not
successful, it should exit with a non-zero exit code.  If successful,
it must exit the process with a zero return code.

(6) A bash command with only "$skip_step_if_already_done" must be executed between
the "check" and the "do" part.

(7) A step must never start another step.  In other words, steps must
never be nested.

(8) The code that invokes a step must follow the invocation with the
command "$prev_cmd_failed".  In addtion to making
bashsteps work (for reasons explained elsewhere), perhaps this
requirement also can serve as a nice reminder that working around
bash's flaws is sometimes necessary, yet easily done in stable,
reliable ways.

(9) Code outside of the step processes must never change external state.
Never, just like the code in the "check" part.

(10) A script should not change the value of a bashsteps hook variable
that has already been set.

(11) (optional) A step can start with a bash command with "$starting_step"
followed by a descriptive string that summarizes the step.  If used,
this command must be before "$skip_step_if_already_done".

That's all!

### (simplifying) Script Assumptions

Having so few requirements is a huge bonus, but it comes with
trade-offs.  Probably the most important trade-off is that bashsteps is
only appropriate for certain types of scripts.  It is difficult to
characterize exactly what makes a script appropriate for bashsteps,
because programming is a creative activity.  A script that at first
does not seem appropriate can easily become so with some creative
insight about how and where the script will be used.

Nevertheless, it is still useful to try to characterize the types of
scripts that are appropriate.  Since the purpose of this page is to
give a complete explanation of the *simplest core part* of bashsteps,
a good place to start a rather restrictive characterization of scripts
that map well to the core:

A)  The script can be divided in a fixed number of non-overlapping
    steps.

B)  The steps can be executed in a fixed, pre-decided order.

C)  The only state that is shared between steps is external to the
    script.  In other words, script variables created by one step are not
    used by another step.

D)  The changes made by the script are additive.  For example, a script
    that installs a package never uninstalls it.

Although restrictive, if one can safely assume these four
characteristics for a planned script, then it is highly likely to be
an appropriate script for bashsteps and that it is possible to be
successful *using only information in this page*.  Common examples of
such scripts would be those that install software or do document
conversion.

See other pages to explore few more hooks and programming requirements
that make bashsteps appropriate for a wider range of scripts.
Remember that bashsteps can be (and has been) used for scripts that do
not meet these criteria.  Other pages also offer less restrictive
criteria to help in judging whether bashsteps would bring benefits for
whatever use is under consideration.

### example

Here is an example script with three steps that meets the requirements:

```
: ${prev_cmd_failed:='eval [ $? == 0 ] || exit #'}
: ${starting_step:=':'}
: ${skip_step_if_already_done:='eval [ $? == 0 ] && exit #'}
: ${starting_group:=':'}
: ${skip_group_if_already_done:=':'}

compile_dir="/tmp/somedir"
(
  [ -d "$compile_dir/server" ]

  $skip_step_if_already_done; set -e
  cd "$compile_dir"
  git clone http://github.com/servers-r-us/server
) ; $prev_cmd_failed

(
  [ -f "$compile_dir/server/Makefile" ]

  $skip_step_if_already_done; set -e
  cd "$compile_dir/server"
  ./configure
) ; $prev_cmd_failed

(
  [ -f "$compile_dir/server/server.bin" ]

  $skip_step_if_already_done; set -e
  cd "$compile_dir/server"
  make
) ; $prev_cmd_failed
```

### Discussion

Assuming that the above script has been saved into a file named
simple-example.sh, consider this experiment: What would happen if the
following is executed?

skip_step_if_already_done='eval exit 0 #'  ./simple-example.sh

Because of coding requirement #10, lines in the script that contain
"$skip_step_if_already_done" make each step's process exit early *such that
no code from "do" parts is executed.* Therefore only the "check" parts and
parts outside of steps will be executed.  Because of coding
requirements #4 and #9, *no state external to the script is changed.*

This is the key mechanism that allows wrapper scripts to customize
script behaviour.  If a wrapper script can assume that (1) running the
script will touch every step and that (2) it can safely avoid changing
state, then many on-the-fly beneficial script enhancements become
possible by setting the hooks appropriately.

Any bashsteps script that you write should have the same property. If
the script is executed with the environment variable
*skip_step_if_already_done* set to 'eval exit 0 #', the script should
produce no external side effects.  This simple test can be used to
catch cases where the coding requirements have not been followed.  The
payoff for your careful coding is a flexible framework with minimal
software requirements.

All the requirements discussed above are part the bashstep's current
core design.  For scripts that meet the above 4 assumptions, this page
supplies everything necessary to achieve an important benefit: that when
a script fails halfway through, re-execution of the script can
continue where it left off.  Time is saved by not repeating steps that
have already been done.  Potentially dangerous side effects from
repeating already done steps are avoided.

The above requirements are not expected to change.  Script that meet
these requirements should work with future bashstep tools.  Tools that
build on top of just these requriments can expect to work with scripts
written in the future.

### Next steps

There are several directions to go from here in introducing bashsteps.

1) The above describes the most important parts of the bashsteps'
   stable core.  The rest is describe on this page:

   starting_step, starting_group, skip_group_if_already_done

2) All of the above may seem arbitrary.  The following pages are
   written more from a motivation perspective and give hints about the
   design tradeoffs and the roadmap.  Some of the known frustrations
   of using bashsteps are discussed.

3) Once the user has put in the effort of splitting the script into
   steps and has coded a check for each step, various automated tools
   become possible.  These pages describe default initilization and
   wrapper scripts that reward the user with more benefits by building
   on bashsteps' stable core.

4) Even though minimal requirements is bashstep's key advantage, there
   are probably additional requirements that would have good payoff.
   The following pages describe such requirements and introduce
   work-in-progress scripts make it possible to start exploring
   potential benefits.  Until there is enough experience showing that
   the benefits justify the extra requirements, these extensions
   should be considered experimental and not a part of core bashsteps.



# previous readme.md contents:

I'm just starting to write the documentation on this.

Note that **bashsteps** is good for some types of scripts, not good
for others.  And there are a bunch of scripts in between for which it
is experimental.  If you are considering using bashsteps (or forced to
use bashsteps), you should **discuss directly with me** about whether
to use it and how to get the most out of it.

An introduction that focuses on motivation is now at
[./doc/intro-to-core.md](./doc/intro-to-core.md).  It keeps the
discussion to the parts of bashsteps that are stable.

An example that exercises the core is at
[./examples/new/with-temporary-state.sh](./examples/new/with-temporary-state.sh).
Probably the next step in documentation is to annotate this example
and show how to give a demo with it.

Also there are comments in [./bashctrl.sh](./bashctrl.sh) and
[./simple-defaults-for-bashsteps.source](./simple-defaults-for-bashsteps.source)
that may give useful hints.
