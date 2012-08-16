#!/bin/sh
#
# dcmd : distributed cmd
# 

VERSION="$Id: dcmd.sh,v 1.11 2008/01/03 04:33:56 cgw Exp $"
progname=$(basename $0)

Usage()
{
    echo "Usage: $progname [options] command host-list [host-list...]"
    echo "  options "
    echo "    --help, -h"
    echo "    --version, -v"
    echo "    --no-hostname, -nh"
    echo "    --no-color, -nc"
    echo "    --timeout=<value>, -t=value"
    echo "    --header-lines=<value>, -l=value"
    echo "  command must be properly quoted, to be a single shell token"
    echo "  host-list has some special expansion, if you use"
    echo "    host[XX] where xx is a decimal number, you will"
    echo "    get a range of names host01 - hostXX (zero-padded)"
    echo "    host[XX-YY] expands out from hostXX to hostYY"
    echo ""
    echo "Example: $progname 'uname -a' dc[3] grid[7] c[10-15]"
}

#defaults
display_hostname=1
use_color=1
header_lines=0
timeout=30

#process options
while grep -q '^-' <<< $1; do
    key=$1
    val=''
    if grep -q = <<< $1; then
	key=$(sed s/=.*// <<< $1)
	val=$(sed s/.*=// <<< $1)
	if [ -z $val ] ; then
	    Usage >&2 ;
	    exit 1;
	fi
    fi
    case $key in
      "--help" | "-h" ) 
	Usage; exit 0
	;;
      "--version" | "-v" ) 
	echo $VERSION; exit 0
	;;
      "--no-hostname" | "-nh" ) 
	display_hostname=0
	;;
      "--no-color" | "-nc" )
        use_color=0
	;;
      "--timeout" | "-t" ) 
	if [ -z $val ] ; then Usage >&2; exit 1; fi
	timeout=$val
	;;
      "--header-lines" | "-l" ) 
	if [ -z $val ] ; then Usage >&2; exit 1; fi
	header_lines=$val
	;;
      *) Usage >&2; exit 1; 
	;;
    esac
    shift
done

cmd=$1
shift

declare -a hosts
max_len=0

for arg in $*; do
    if fgrep -q \[ <<< $arg; then
	## (Overly?) fancy expansion of [] in hostnames
	# Pull out bracketed expression
	brkt=$(sed 's/.*\[\(.*\)\].*/\1/' <<< $arg)
	# If there is a hyphen, it is a range of numbers
	if grep -q -- - <<< $brkt; then
	    num1=$(sed 's/-.*//' <<< $brkt)
	    num2=$(sed 's/.*-//' <<< $brkt)
	else # otherwise it is 1-N
	    num1=1
	    num2=$brkt
	fi
	# Format everything to the width of "num2"
	fmt=$(sed 's/\[.*\]/%0'${#num2}'g/' <<< $arg)
	for x in $(seq -f $fmt $num1 $num2); do
	    hosts=(${hosts[*]} $x)
	done
    else
	hosts=(${hosts[*]} $arg)
    fi
done

tmpdir=/tmp/$progname-tmp.$$.d/
mkdir -p $tmpdir
trap "rm -rf $tmpdir" exit

N=${#hosts[*]}

## Is there a way to do this with process
## substitution or FIFOs or something so
## we don't have to create these tmpfiles?

for ((i=0; i<$N; i++)) ; do
    host=${hosts[$i]}
    if [ ${#host} -gt $max_len ] ; then
	max_len=${#host}
    fi
    ssh -oStrictHostKeyChecking=no -n $host "$cmd" 2>$tmpdir/$host.stderr > $tmpdir/$host &
done
(( max_len = max_len + 4))
while [ $timeout -gt 0 ] ; do
    n_jobs=`jobs -r | wc -l`
    if [ $n_jobs  -eq 0 ] ; then
	break
    else
	sleep 1
	((timeout--))
    fi
done

if [ $n_jobs -gt 0 ] ; then
    echo "Warning " $n_jobs " jobs timed out"
fi

for ((i=0; i<$N; i++)) ; do
    host=${hosts[$i]}  
    cat $tmpdir/$host | (lineno=1; while read line; do
	display=$host
	[[ $i -eq 0 && $lineno -le $header_lines ]] && display="Host"    
        [[ $i -eq 0 || $lineno -gt $header_lines ]] && ( 
            [ $display_hostname -ne 0 ] && printf "%-0${max_len}s" ${display}
            echo "$line")
        (( lineno++ ))
        done)
    if [ -s $tmpdir/$host.stderr ] ; then
	[ $use_color -ne 0 ] && echo -n -e \\x1b\[01\;31m
	cat $tmpdir/$host.stderr | ( while read line; do
	    [ $display_hostname -ne 0 ] && printf "%-0${max_len}s" $host    
	    echo "$line"
	done)
	[ $use_color -ne 0 ] && echo -n -e \\x1b\[00m
    fi	    
done
[ $use_color -ne 0 ] && echo -n -e \\x1b\[00m
