#!/bin/bash

#PBS -l select=1:ncpus=1:mem=7900mb

pn=$(basename $0)
commandline="$pn $*"

msg () {
    for msgline
    do echo "$pn: $msgline" >&2
    done
}

fatal () { msg "$@"; exit 1; }

normalpath () {
    local s=$1
    [[ $s == ${s::400} ]] || fatal "Option path too long"
    [[ $s == ${s//[^[:print:]]/} ]] || fatal "Non-printables in path"
    dir=$(dirname "$1")
    bas=$(basename "$1")
    echo $(cd $dir && pwd)/$bas
}

tempdir () {
    : ${TMPDIR:="/tmp"}
    tdbase=$TMPDIR/$USER
    test -e $tdbase || mkdir -p $tdbase
    td=$(mktemp -d $tdbase/$(basename $0).XXXXXX) || fatal "Could not create temp dir in $tdbase"
    echo $td
}

set -e   # Terminate script at first error

idx=$1
if [[ -z $idx ]] ; then idx=$PARALLEL_SEQ ; fi

wd=$PWD
if [[ -z $wd ]] ; then wd=$PWD ; fi

if [[ $ARCH == "bash" ]]
then
    td=$(tempdir)
    cd $td
fi

set -- $(head -n $idx $wd/job.conf | tail -n 1)

while [ $# -gt 0 ]
do
    case "$1" in
	-tgt)               tgt=$(normalpath "$2"); shift;;
	-src)               src=$(normalpath "$2"); shift;;
	-srctr)           srctr=$(normalpath "$2"); shift;;
	-msk)               msk=$(normalpath "$2"); shift;;
	-masktr)         masktr=$(normalpath "$2"); shift;;
	-alt)               alt=$(normalpath "$2"); shift;;
	-alttr)           alttr=$(normalpath "$2"); shift;;
	-dofin)           dofin=$(normalpath "$2"); shift;;
	-dofout)         dofout=$(normalpath "$2"); shift;;
	-spn)               spn=$(normalpath "$2"); shift;;
	-tpn)               tpn=$(normalpath "$2"); shift;;
	-lev)               lev="$2"; shift;;
	--) shift; break;;
        -*)
            fatal "Parameter error" ;;
	*)  break;;
    esac
    shift
done

if [[ $lev == 0 ]] ; then
    cat >lev0.reg << EOF

#
# Registration parameters
#

No. of resolution levels          = 2
No. of bins                       = 64
Epsilon                           = 0.0001
Padding value                     = -1
Source padding value              = -1
Similarity measure                = NMI
Interpolation mode                = Linear

#
# Registration parameters for resolution level 1
#

Resolution level                  = 1
Target blurring (in mm)           = 1
Target resolution (in mm)         = 2 2 2
Source blurring (in mm)           = 1
Source resolution (in mm)         = 2 2 2
No. of iterations                 = 40
Minimum length of steps           = 0.01
Maximum length of steps           = 1

#
# Registration parameters for resolution level 2
#

Resolution level                  = 2
Target blurring (in mm)           = 2
Target resolution (in mm)         = 5 5 5
Source blurring (in mm)           = 2
Source resolution (in mm)         = 5 5 5
No. of iterations                 = 40
Minimum length of steps           = 0.01
Maximum length of steps           = 2

EOF

dofcombine "$spn" "$tpn" pre.dof.gz -invert2
echo rreg2 "$tgt" "$src" -dofin pre.dof.gz -dofout dofout.dof.gz -parin lev0.reg
rreg2 "$tgt" "$src" -dofin pre.dof.gz -dofout dofout.dof.gz -parin lev0.reg >reg0-$idx.log 2>&1
fi

if [[ $lev == 1 ]] ; then
    
    cat >lev1.reg << EOF

#
# Registration parameters
#

No. of resolution levels          = 2
No. of bins                       = 64
Epsilon                           = 0.0001
Padding value                     = 0
Source padding value              = 0
Similarity measure                = NMI
Interpolation mode                = Linear

#
# Registration parameters for resolution level 1
#

Resolution level                  = 1
Target blurring (in mm)           = 0
Target resolution (in mm)         = 0 0 0
Source blurring (in mm)           = 0
Source resolution (in mm)         = 0 0 0
No. of iterations                 = 40
Minimum length of steps           = 0.01
Maximum length of steps           = 1

#
# Registration parameters for resolution level 2
#

Resolution level                  = 2
Target blurring (in mm)           = 1.5
Target resolution (in mm)         = 3 3 3
Source blurring (in mm)           = 1.5
Source resolution (in mm)         = 3 3 3
No. of iterations                 = 40
Minimum length of steps           = 0.01
Maximum length of steps           = 1

EOF

echo areg2 "$tgt" "$src" -dofin "$dofin" -dofout dofout.dof.gz -parin lev1.reg
areg2 "$tgt" "$src" -dofin "$dofin" -dofout dofout.dof.gz -parin lev1.reg >reg1-$idx.log 2>&1
fi

if [[ $lev == 2 ]] ; then
cat >lev2.reg << EOF

#
# Non-rigid registration parameters
#

Lambda1                           = 0.0001
Lambda2                           = 1
Lambda3                           = 1
Control point spacing in X        = 6
Control point spacing in Y        = 6
Control point spacing in Z        = 6
Subdivision                       = True
MFFDMode                          = True

#
# Registration parameters
#

No. of resolution levels          = 1
No. of bins                       = 128
Epsilon                           = 0.0001
Padding value                     = 0
Source padding value              = 0
Similarity measure                = NMI
Interpolation mode                = Linear

#
# Skip resolution level 1
#

Resolution level                  = 1
Target blurring (in mm)           = 0
Target resolution (in mm)         = 0 0 0
Source blurring (in mm)           = 0
Source resolution (in mm)         = 0 0 0
No. of iterations                 = 40
Minimum length of steps           = 0.01
Maximum length of steps           = 2

EOF

echo nreg2 "$tgt" "$src" -dofin "$dofin" -dofout dofout.dof.gz -parin lev2.reg
nreg2 "$tgt" "$src" -dofin "$dofin" -dofout dofout.dof.gz -parin lev2.reg >reg2-$idx.log 2>&1
fi

transformation "$msk" masktr.nii.gz -linear -dofin dofout.dof.gz -target "$tgt" && cp masktr.nii.gz "$masktr"
transformation "$src" srctr.nii.gz -linear -dofin dofout.dof.gz -target "$tgt" && cp srctr.nii.gz "$srctr"
transformation "$alt" alttr.nii.gz -linear -dofin dofout.dof.gz -target "$tgt" && cp alttr.nii.gz "$alttr"
cp dofout.dof.gz "$dofout"
