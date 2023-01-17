#!/bin/bash
# set -x
FBDIR=Xvfb-FB
BOLD='\033[1m' 
RED='\033[0;31m' 
GREEN='\033[0;32m' 
BLUE='\033[0;34m' 
NC='\033[0m'
DETAILS=$FBDIR/inputrc-test
DETAILS_EXP=$DETAILS.expect
DETAILS_GOT=$DETAILS.got

mkdir -p $FBDIR
rm -f $FBDIR/*
touch $FBDIR/history.old
touch $FBDIR/history

HEADLESS=true
[ "$1" == "--no-headless" ] && HEADLESS=false

SLEEP="sleep .01"
SUDO="sudo"
$SUDO echo -n ''

setup () {
    local CMD="source misc/inputrc-test-init.sh; script -f $FBDIR/typescript.0"
    echo Setup
    $HEADLESS   && xvfb-run -s "-fbdir $FBDIR" xterm -e "$CMD" &
    ! $HEADLESS && xterm -e "$CMD" &

    # check if starting succeeded
    for i in {1..10} ; do
        sleep 1
        PID=$(ps a | grep -Ev 'xvfb|grep|xterm|inputrc-test-init' | grep "script -f"  | awk '{print $1}')
        PTS=$(ps a | grep -Ev 'xvfb|grep|xterm|inputrc-test-init' | grep "script -f"  | awk '{print $2}')
        [ -n "$PTS" ] && break
    done
    echo $PID $PTS
    pstree -sp $PID \
        | grep "$(basename $0)($$)" >&/dev/null\
        || { echo -e "${RED}Can't find test process. Exiting.${NC}"; exit 1; }
    echo -e ${BLUE}Started xterm on $PTS with pid $PID${NC}
    echo 

    trap "kill $PID" TERM EXIT KILL
    TTY=/dev/$PTS
    writetty 'source misc/inputrc-test-init.sh\n'
}

initcnt     () { ls -1 $FBDIR/typescript.* 2>/dev/null | tail -1 | perl -pe '~s/.*?(\d+)$/$1/' ; }
iofiles     () { ls -1 $FBDIR/typescript.* 2>/dev/null | perl -ne '/(\d+)$/;$a{int($1)}=$_; END{@r=sort {$a <=> $b}  keys %a; print $a{$r[0]},$a{$r[-1]}}' ; }
storets     () { j=$(initcnt); j=$((j+1)); cp $FBDIR/typescript.0 $FBDIR/typescript.$j ; }
storehist   () { cp $FBDIR/history $FBDIR/history.old; }
writetty    () { storets; $SLEEP; $SUDO perl misc/ioctl2.pl $TTY "$@" >& /dev/null ; }
readtty     () { tail $1 $FBDIR/typescript.0 | tee $FBDIR/READPROMPT | head -1; }
rmprompt    () { perl -pe '~/^\w+\@\w+/ || exit 1; ~s|^.*?\$\s*||'; }
awaitts     () { while diff $(iofiles) >& /dev/null ; do sleep .01; done; }
teardown    () { writetty 'history -r; exit\n' ; }
awaithist   () { while diff $FBDIR/hist* >& /dev/null ; do sleep .01; done; }
clrprompt   () { writetty '\e[1;5B\er\n\n'; }

read_prompt     () { awaitts; readtty -1 | rmprompt ; }
read_history    () { storehist; writetty '\nhistory -w\n'; awaithist; tail -3 $FBDIR/history | head -1 | perl -pe 's/[\r\n]+$//' ; }
read_prompt_oct () { read_prompt | hexdump -b | head -1 | perl -pe 's/\s+/ /;s/^[\d]+\s+//;s/\s+\n//;' ; }
read_stdout     () { awaitts; readtty $1 | tr -d '\n' | tr -d '\r' ; }


expect      () { 
    echo -n "$1" > $DETAILS_EXP;
    tee $DETAILS_GOT >&/dev/null
    diff $DETAILS* >&/dev/null
}
details     () { 
    echo -en      "${GREEN}" "\texpect: "; cat ${DETAILS_EXP}
    echo -en "\n" "${RED}"   "\tgot   : "; cat ${DETAILS_GOT}
    echo -e  "${NC}"
}

runtest () { 
    local testfunc=$1
    eval "local -n args=${testfunc}_args"
    printf "%-40s %-80s" "Binding '${args[binding]}'" "${args[description]} ..."
    $testfunc  && echo -e "${BOLD}${GREEN}PASSED${NC}" \
        || { echo -e "${BOLD}${RED}FAILED${NC}"; details; read; }
    clrprompt
}

write_input () {
    eval "local -n args=${1}_args"
    [ -n "${args[first_write]}" ] && writetty "${args[first_write]}"
    writetty "${args[binding]}"
    [ -n "${args[then_write]}" ]  && writetty "${args[then_write]}"
}
cmp_with () {
    eval "local -n args=${1}_args"
    read_${args[cmp_with]} | expect "${args[expect]}"
}

cmp_output () {
    eval "local -n args=${1}_args"
    [ -z "${args[expect_out]}" ] && return 0
    read_stdout -2 | expect "${args[expect_out]}"
}

o_default_args () {
    eval "local -n args=${1}_args"
    args[description]="$2"
    [ -z "${args[maps_to]}"  ] && args[maps_to]="${args[expect]}"
    args[maps_to]="\"${args[maps_to]}\""
    [ -n "${args[func]}"  ] && args[maps_to]="${args[func]}"
    [ -z "${args[cmp_with]}" ] && args[cmp_with]='prompt'
    # for i in first_write expect expect_out then_write cmp_with ; do
    #     printf "%-15s: %s\n" "$i" "[${args[$i]}]"
    # done
    eval "$1 () { write_input $1; cmp_output $1 && cmp_with $1; }"
}

TESTCNT=0
o () {
    TESTCNT=$(($TESTCNT+1))
    eval "declare -A test${TESTCNT}_args"
    local OIFS=$IFS IFS=$'\n' arg argval description
    for arg in "$@" ; do 
        [[ "$arg" =~ = ]] && { 
            argval="${arg#*=}"
            argval="${argval//$/\\\$}"
            argval="${argval//~\/~/=}"
            eval "test${TESTCNT}_args[${arg%=*}]=\"$argval\"" ; 
            continue
        }
        arg="${arg//~\/~/=}"
        description="$description $arg"
    done
    IFS=$OIFS
    o_default_args test$TESTCNT "$description"
    local -n args=test${TESTCNT}_args
    runtest test$TESTCNT && \
        printf "%-25s %-50s # %s\n" \
            "\"${args[binding]}\":" \
            "${args[maps_to]}" \
            "${args[description]}" >> $FBDIR/result_inputrc
}
HEAD_DELIM=$(perl -e "print '# ', '-' x 140, \"\n\"" )
= () {
    local text="${@}"
    echo -e "\n\033[1m$text\033[0m"
    { [ -z "$1" ] && echo -e ""  && return
      echo "$HEAD_DELIM"
      echo -e "# $text" >> $FBDIR/result_inputrc
      echo "$HEAD_DELIM"
    } >> $FBDIR/result_inputrc
}
set () { echo set "$@" >> $FBDIR/result_inputrc; }
sss () { echo -e "$@" >> $FBDIR/result_inputrc; }
if="sss \$if"
endif="sss \$endif"

setup

echo -e "# This file was generated automatically !!!\n" >> $FBDIR/result_inputrc

set show-all-if-ambiguous on
set show-all-if-unmodified on
set mark-symlinked-directories on
set completion-prefix-display-length 8
set completion-ignore-case on
set completion-map-case on
set page-completions off
set colored-stats on
set colored-completion-prefix on
set visible-stats on
set input-meta on
set output-meta on
set convert-meta off

=; =;
$if Bash
= Helper bindings

o binding='\e[1~\eh'    cuts last word of previous history command \
                            first_write='echo Cutting the last word\n' \
                            cmp_with='history' expect='echo Cutting the last' \
                            maps_to='\e[A\C-b\C-b \C-k\C-k'
o binding='\e[1~\em'    cuts first word of previous history command \
                            first_write='echo Now cutting the first word\n' \
                            cmp_with='history' expect='Now cutting the first word' \
                            maps_to='\e[A\e[H\C-b \C-u\e[3~\e[F'
o binding='\e[1~\e?'    removes first occurence of '?' before the cursor \
                            first_write='This ? text ? Really ? Yes!' \
                            cmp_with='history' expect='This ? text ? Really  Yes!' \
                            maps_to='\C-b\C-b?\e[3~\e.'
o binding='\e[1~\el\eh' inserts a for loop header with loop var i \
                            expect='for i in'
o binding='\e[1~\el\eb' inserts a for loop body with loop var i \
                            expect='; do echo $i? ; done' 
o binding='\e[1~\el'    inserts a for loop with loop var i : \
                            expect='for i in * ; do echo $i? ; done'
o binding='\e[2~\el\eh' inserts a for loop header with loop var j : \
                            expect='for j in'   
o binding='\e[2~\el\eb' inserts a for loop body with loop var j : \
                            expect='; do echo $j? ; done'
o binding='\e[99~'      moves cursor left then right \
                            first_write='a' cmp_with='prompt_oct' \
                            expect='141 007 010' maps_to='\e[C\e[D'

=;= Dump manuals for commands: "(h)elp - (l)ong, (s)hort, (m)anpage"
o binding='\eh\el'      executes "'--help'" after a command \
                            first_write='grep' then_write='\ez' cmp_with='history' \
                            expect_out='Called grep --help' expect='grep --help' \
                            maps_to='\e[F --help\C-m\e[1~\eh'
o binding='\eh\es'      executes "'-h'" after a command \
                            first_write='grep' then_write='\ez' cmp_with='history' \
                            expect_out='Called grep -h' expect='grep -h' \
                            maps_to='\e[F --h\C-m\e[1~\eh'
o binding='\eh\em'      executes "'man'" before a command \
                            first_write='grep' then_write='\ez' cmp_with='history' \
                            expect_out='Called man wrapper for grep' expect='man grep' \
                            maps_to='\e[Hman \C-m\e[1~\em'

=;= Insert commands: "(i)nsert - ($)ubshell, (l)oop, ..."
o binding='\eI\e$'      inserts subshell '"$(<cursor>)"' \
                            then_write='echo xy\n' cmp_with='history' \
                            expect_out='Called xy' expect='$(echo xy )' \
                            maps_to='$(?)\e[1~\e? \e[D'
o binding='\ei\el'      inserts loop with i '"for i in <*> ; do echo $i? ; done)"' \
                            then_write='1\n' cmp_with='history' \
                            expect_out='1*?' expect='for i in 1* ; do echo $i? ; done' \
                            maps_to='\e[1~\el\C-b\C-b*'
o binding='\ei\el\eb'   goes to loop body '"for i in * ; do <cursor> ; done)"' \
                            first_write='\ei\el1' then_write='echo $i\n' cmp_with='history' \
                            expect_out='1*' expect='for i in 1* ; do echo $i ; done' \
                            maps_to='\C-b?\C-h\C-h\e[3~'
o binding='\eI\eI'      backup and set "IFS~/~\$'\\n'" \
                            expect="OLDIFS~/~\$IFS; \$IFS~/~\$'\\n'; "
o binding='\ei\eg'      inserts grep "'<cursor>'" \
                            then_write='Hello\n' cmp_with='history' \
                            expect_out='Called grep Hello' expect="grep 'Hello'" \
                            maps_to='grep '?'\e[1~\e?'
o binding='\ei\eg\ee'   inserts grep -E "'<cursor>'" \
                            then_write='Hello\n' cmp_with='history' \
                            expect_out='Called grep -E Hello' expect="grep -E 'Hello' " \
                            maps_to='grep -E '?'\e[1~\e?'
o binding='\ei\eg\ev'   inserts grep -v "'<cursor>'" \
                            then_write='Hello\n' cmp_with='history' \
                            expect_out='Called grep -v Hello' expect="grep -v 'Hello' " \
                            maps_to='grep -v '?'\e[1~\e?'
o binding='\ei\eg\ee\ev' inserts grep -Ev "'<cursor>'" \
                            then_write='Hello\n' cmp_with='history' \
                            expect_out='Called grep -Ev Hello' expect="grep -Ev 'Hello' " \
                            maps_to='grep -Ev '?'\e[1~\e?'
# "\ei\es":        "sed -re 's/?//'\e[1~\e?"              # insert sed -re 's|<?>||'
# "\eI\eS":        " -e 's/?//' \e[1~\e?"                 # insert -e 's/<?>//'
# "\ei\es\et":     "sed -n  '/^?/,/^/p'\e[1~\e?"          # insert sed -n '/<?>/,//p'

o binding='\ei\ed'      inserts cmd delimiter at next blank \
                            first_write='grep arg1 grep arg2\e[H\e[1;3C' cmp_with='history' \
                            expect='grep arg1 ; grep arg2' \
                            maps_to='\e.\C-b  ;\C-x\C-x'

=;= Insert at EOL: "at (E)ol, e.g. (S)ed match"
# insert at (e)ol, e.g. (s)ed
# "\eE\eS":     "\e[F\eI\eS"                              # at EOL append sed subst s///

=;= Append pipe to line: "(p)ipe to (a)pp, e.g. (p)ipe to (g)rep"
# "\ep\eg":           " | \ei\eg\e[99~"                   # pipe to grep
# "\ep\eg\ee":        " | \ei\eg\ee\e[99~"                # pipe to grep -E
# "\ep\eg\ev":        " | \ei\eg\ev\e[99~"                # pipe to grep -v
# "\ep\eg\ee\ev":     " | \ei\eg\ee\ev"                   # pipe to grep -Ev
# "\ep\ea":           " | awk '{print ?}' \e[1~\e?"       # pipe to awk
# "\ep\ea\en":        " | awk NF"                         # pipe to awk NF / remove empty lines
# "\ep\ex":           " | xargs "                         # pipe to xargs
# "\ep\el":           " | less "                          # pipe to less
# "\ep\et":           " | tail "                          # pipe to tail
# "\ep\er":           " | read X\e[D"                     # pipe to read
# "\ep\ep\ep":        " | perl -pe ' '\e[D\e[D"           # pipe to perl -pe
# "\ep\ep":           " | perl -ne ' '\e[D\e[D"           # pipe to perl -ne
# "\ep\es":           " | sed -re '/?/'\e[1~\e?"          # pipe to sed //
# "\ep\es\es":        " | sed -re 's/?//'\e[1~\e?"        # pipe to sed s///
# "\ep\ew":           " | wc -l "                         # pipe to wc -l
# "\ep\ew\ec":        " | wc -c "                         # pipe to wc -c
# "\ep\et":           " | tee "                           # pipe to tee
# "\ep\et\ea":        " | tee -a "                        # pipe to tee -a
# "\eP\eS":           " | sort "                          # pipe to sort
# "\eP\eS\eU":        " | sort -u "                       # pipe to sort -u
# "\ep\ep\eg":        "\e[F\ep\eg\e[99~"                  # pipe at EOL to grep
# "\ep\ep\eg\ee":     "\e[F\ep\eg\ee\e[99~"               # pipe at EOL to grep -E
# "\ep\ep\eg\ev":     "\e[F\ep\eg\ev\e[99~"               # pipe at EOL to grep -v
# "\ep\ep\eg\ee\ev":  "\e[F\ep\eg\ee\ev\e[99~"            # pipe at EOL to grep -Ev
# "\ep\ep\ea":        "\e[F\ep\ea\e[99~"                  # pipe at EOL to awk
# "\ep\ep\ea\en":     "\e[F\ep\ea\en\e[99~"               # pipe at EOL to awk NF / remove empty lines
# "\ep\ep\ex":        "\e[F\ep\ex\e[99~"                  # pipe at EOL to xargs
# "\ep\ep\el":        "\e[F\ep\el\e[99~"                  # pipe at EOL to less
# "\ep\ep\et":        "\e[F\ep\et\e[99~"                  # pipe at EOL to tail
# "\ep\ep\er":        "\e[F\ep\er\e[99~"                  # pipe at EOL to read
# "\ep\ep\ep\ep":     "\e[F\ep\ep\ep\e[99~"               # pipe at EOL to perl -pe
# "\ep\ep\ep":        "\e[F\ep\ep\e[99~"                  # pipe at EOL to perl -ne
# "\ep\ep\es":        "\e[F\ep\es\e[99~"                  # pipe at EOL to sed //
# "\ep\ep\es\es":     "\e[F\ep\es\es\e[99~"               # pipe at EOL to sed s///
# "\ep\ep\ew":        "\e[F\ep\ew\e[99~"                  # pipe at EOL to wc -l
# "\ep\ep\ew\ec":     "\e[F\ep\ew\ec\e[99~"               # pipe at EOL to wc -c
# "\ep\ep\et":        "\e[F\ep\et\e[99~"                  # pipe at EOL to tee
# "\ep\ep\ew\ea":     "\e[F\ep\et\ea\e[99~"               # pipe at EOL to tee
# "\eP\eP\eS":        "\e[F\eP\eS\e[99~"                  # pipe at EOL to sort
# "\eP\eP\eS\eU":     "\e[F\eP\eS\eU\e[99~"               # pipe at EOL to sort -u

# (r)edirect std(o)ut, std(e)rr, (a)ll
# "\er\ei":          " 1> "
# "\er\ee":          " 2> "
# "\er\ea":          " >& "
# "\er\ei\en":       " 1> /dev/null"
# "\er\ee\en":       " 2> /dev/null"
# "\er\ea\en":       " >& /dev/null"

# # pr(e)fix or e(x)ecute prefixed line: e.g. (e)xport, (s)udo, ...
# "\ee\ee":       "\e.\e[Hexport \C-x\C-x\e[7C"
# "\ee\es":       "\e.\e[Hsudo \C-x\C-x\e[5C"
# "\ex\ee":       "\ee\ee\C-m"
# "\ex\es":       "\ee\es\C-m"

# # embrace line
# "\e$":          "\e[H$\(\e[F) "                                   # subshell $(..)
# "\e\"":         "\e[H\"\e[F\" "                                   # quote "..."
# "\e'":          "\e[H'\e[F' "                                     # quote '...'
# "\el":          "\e[H\e[1~\el\eh \e[F\e[1~\el\eb\e[1~\e?\C-i\C-i" # for loop $i
# "\el\ej":       "\e[H\e[2~\el\eh \e[F\e[2~\el\eb\e[1~\e?\C-i\C-i" # for loop $j
# "\eI"           "\e[H\eI\eI\e[F; \eI\eI\eR"                       # IFS=$'\n' and reset

# comments
# "\e+":          "\e.\e[H\e[3~\C-x\C-x\e[D"                       # uncomment (see \e#)
# "\e+\e+":       "\e+\e[F"                                        # uncomment, enforce cursor to end

# move cursor
# "\e[1;7H": "\C-b\C-b "                                         # backward to next blank
# "\e[1;7F": "\C-b "                                             # forward to next blank

# session
# "\C-x\C-d": "history -r \er\C-D"
$endif

# admin helpers
# "\C-v":         quoted-insert
# "\C-x\C-r":     re-read-init-file
# "\C-x\C-v":     display-shell-version

# macro recording
# "\e[1;5P":      start-kbd-macro          # Ctrl + F1
# "\e[1;5Q":      end-kbd-macro            # Ctrl + F2
# "\e[1;5R":      call-last-kbd-macro      # Ctrl + F3
# "\e[1;5S":      print-last-kbd-macro     # Ctrl + F4
# "\e[15;5~":     dump-macros              # Ctrl + F5

# (shell-)completion
# "\ey":          menu-complete
# "\ex":          menu-complete-backward
# "\C-i":         complete

# Actually most of the following completion looks useful 
# when you don't use a state of the art competion system.
# But the first 3 (maybe 4) are really useful.
# "\e(":          complete-into-braces        # :-)
# "\ed":          dabbrev-expand              # :-)
# "\eh":          dynamic-complete-history    # :-)
# "\ep":          possible-completions        # :-)

# "\e!\el":       possible-command-completions
# "\e/\el":       possible-filename-completions
# "\e@\el":       possible-hostname-completions
# "\e~\el":       possible-username-completions
# "\ev\el":       possible-variable-completions

# "\e!":          complete-command
# "\e/":          complete-filename
# "\e@":          complete-hostname
# "\e~":          complete-username
# "\ev":          complete-variable

# "\C-g\C-w":     glob-complete-word
# "\C-g\C-w\C-x": glob-expand-word
# "\C-g\C-l\C-x": glob-list-expansions

# "\ec":          insert-completions
# "\eH":          history-expand-line

=;= History bindings
o binding='\e[A'        can access previous history command \
                            first_write='echo test\n' \
                            expect='echo test' func='previous-history'


# history: navigate and search
# "\e[A":         previous-history             # <up>
# "\e[B":         next-history                 # <down>
# "\e[1;3A":      history-search-backward      # Meta + <up>
# "\e[1;3B":      history-search-forward       # Meta + <down>
# "\e[1;5A":      beginning-of-history         # Ctrl + <up>
# "\e[1;5B":      end-of-history               # Ctrl + <down>
# "\C-r":         reverse-search-history
# "\C-s":         forward-search-history

# # editor: overall
# "\e[2~":        overwrite-mode               # Insert
# "\C-l":         clear-screen
# "\e\C-l":       clear-screen
# "\e:":         delete-horizontal-space

# # editor: LINES: move, delete, modify 
# "\e[H":         beginning-of-line            # Home
# "\e[F":         end-of-line                  # End
# "\e[1;3F":      kill-line                    # Meta + Fn + =>
# "\e[1;5F":      kill-line                    # Ctrl + Fn + =>
# "\e[1;3H":      backward-kill-line           # Meta + Fn + <=
# "\e[1;5H":      backward-kill-line           # Ctrl + Fn + <=
# "\C-x\C-r\C-l": redraw-current-line

# "\C-u":         unix-line-discard
# "\C-k":         kill-line
# "\C-u\C-u":     kill-whole-line

# # editor: WORDS: move, delete, modify 
# "\e[1;3C":      forward-word                 # Meta + =>
# "\e[1;3D":      backward-word                # Meta + <=
# "\e[1;5C":      forward-word                 # Ctrl + =>
# "\e[1;5D":      backward-word                # Ctrl + <=
# "\e[1;4C":      kill-word
# "\e[3;5~":      kill-word
# "\e[1;4D":      backward-kill-word           # Meta + Shift + <=
# "\e\C-?":       backward-kill-word           # Meta + Backspace
# "\C-h":         backward-kill-word           # Ctrl + Backspace / Ctrl + H
# "\C-wu":        upcase-word
# "\C-wd":        downcase-word
# "\C-wc":        capitalize-word
# "\e\C-t":       transpose-words

# # editor: CHARS: move, delete, modify 
# "\e[C":         forward-char                  # =>
# "\e[D":         backward-char                 # <=
# "\e[3~":        delete-char                   # Del
# "\C-?":         backward-delete-char          # Backspace
# "\C-b":         character-search
# "\C-b\C-b":     character-search-backward
# "\et":          transpose-chars

# # editor: MISC: insert, expand and query data
# "\e#":          insert-comment
# "\ea":          insert-last-argument
# "\C-x\C-x":     exchange-point-and-mark
# "\C-@":         set-mark
# "\e.":          set-mark
# "\C-x\C-k":     kill-region

# # # dump-functions (not bound)
# # # dump-variables (not bound)
# # # alias-expand-line (not bound)

# # editor: copy, paste, insert, undo, discard, accept
# "\C-y\C-r":     copy-region-as-kill
# "\C-y\C-b":     copy-backward-word
# "\C-y\C-f":     copy-forward-word
# "\C-y":         yank

# "\e_":          yank-last-arg
# "\e=":          yank-nth-arg
# "\ev":          yank-pop

# "\ez":          undo
# "\eu":          undo
# "\er":          revert-line
# "\C-m":         accept-line

# "\C-o":         operate-and-get-next
# "\C-x\C-e":     edit-and-execute-command

! $HEADLESS && read -p "Exit? Press key. "

teardown
exit
