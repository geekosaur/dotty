:

# X11.app braindamage hackaround
case "x`uname`+$-" in
xDarwin+*i*)
    type stty >/dev/null 2>&1 || PATH=/usr/bin:/bin # @@@ wtf?
    test -t 1 && stty erase '^?' || set +i
    ;;
esac

case "x$-" in
x*i*)
    if [ "x$ZSH_NAME" = x ] && [ -f /usr/local/bin/zsh ] && [ "x$NOZSH" = x ]; then
	if [ "x$SHLVL" = x1 ]; then
	    opt="-l +F"
	else
	    opt=
	fi
	export SHELL=/usr/local/bin/zsh
	exec /usr/local/bin/zsh $opt
    fi
    if [ "x$ZSH_NAME" = x ] && [ -f /bin/zsh ] && [ "x$NOZSH" = x ]; then
	if [ "x$SHLVL" = x1 ]; then
	    opt="-l +F"
	else
	    opt=
	fi
	export SHELL=/bin/zsh
	exec /bin/zsh $opt
    fi
    # quick hack so zsh doesn't screw us later
    if [ "x$ZSH_NAME" != x ]; then
	setopt shwordsplit
    fi
    ;;
esac
# new screen sessions should be reset for sanity
case "$_BSA_SCREEN:$STY" in
set:*)
    ;;
:)
    ;;
*)
    _BSA_SCREEN=set
    export _BSA_SCREEN
    unset XAUTHORITY DISPLAY SSH_TTY SSH_CONNECTION SSH_CLIENT _BSA_SH_LEVEL
    ;;
esac
#
# This horrendous kludge needs some explanation.  :-)
#
# There are two core mechanisms in here.  The first is that I prefer to be
# able to create windows which are in separate authentication groups when
# using AFS and/or Kerberos; the second is that I keep track of these windows
# (and even windows in the same authentication group but with other attributes
# that may differ) by modifying the prompt and/or the window title.
#
# This is complicated by the following:
#
# (1) bash 2.01 (only) drops core when you try to specify a "trap ... 0", so
#     it can't clean up Kerberos ticket caches after itself;
# (2) AFS tokens, Kerberos tickets, and OS uids are not only not necessarily
#     related, but indeed may all be completely different;
# (3) finding a real program (as opposed to our wrapper aliases and functions)
#     can be difficult.
#
# Rather than try to intuit whether we should get tickets, which fails
# when tickets are only intermittently desired (e.g. my home machine),
# we check for a semaphore file.  If ~/.nokerb exists, we don't get
# tickets automatically.
#
# This gets pretty sad.
#
# We have the following cases:
#
# Kerberos 5 with NRL AFS mods, or Kerberos 4 with KTH mods:
#	no restrictions, one operation gets both.  Except that
#	the AFS "admin" token cannot be handled this way.
#	(Correction:  KTH afslog can't handle it.  Prefer aklog/cklog,
#	which can.)
#
# Kerberos 5 unmodified, Kerberos 4 + KTH, AFS:
#	Kerberos 5 is out of sync with Kerberos 4 and AFS, and
#	we must beware of "admin".
#
# Kerberos 5 or Kerberos 4, unmodified, plus AFS:
#	Kerberos is completely out of sync with AFS.
#
# Kerberos 5 or Kerberos 4, regardless of mods, without AFS:
#	no restrictions.
#
# AFS, no standalone Kerberos:
#	no restrictions.
#
# In all cases except when Kerberos 5 is independent of AFS, Kerberos
# 5 wins over Kerberos 4.  If Kerberos 5 is independent, we ignore it
# (for now).  This may change if e.g. Sun Secure RPC is needed in the
# future.  (Except that the strings in Solaris /usr/bin/kinit look more
# like Kerberos 4.  ???)
#
# Then there's an additional complication:  we may have Arla instead of
# AFS.  (Coda?  I'll worry about it when I see more than kernel code.)
#
# Determining what kind of support we have is somewhat tricky, but we can
# look for key commands:
#
# klog => AFS
# kinit => Kerberos of some kind
# aklog => Kerberos with AFS support (includes non-KTH Kerberos 4 with AFS)
# kauth => KTH Kerberos 4
# ksu => MIT Kerberos 5
# verify_krb5_conf => Heimdal / KTH Kerberos 5
#
# (NB.  Arla without either KTH Kerberos 4 or AFS userspace commands is not
# recognized.  That's okay, since it implies that no authentication is wanted,
# and we are only interested in authentication.)
#
# It's not enough to simply locate the above, as one might have both Kerberos
# 5 and KTH Kerberos 4 (or some other combo) and we must use all utilities from
# the same source (except that AFS utilities are OK in a Kerberos environment).
# But the latter may need some protection:  some sites install klog.krb as
# klog (or in the case of Linux, klog *is* klog.krb), but if we have Kerberos
# we need to have klog ignore the ticket file; it is not compatible between
# klog and Kerberos 5 and appears to be incompatible with KTH as well.
#
# One more complication:  given an AFS-enabled Kerberos, we will have one
# ticket file on login which is named after the uid.  We must immediately
# move this elsewhere so it's safe against multiple concurrent logins, and
# we save the new name to use as a bootstrap for new sessions.  Which last
# means that we can start up with tickets (or can get tickets without going
# through a login procedure) but no token.  Since this will only happen with
# AFS-ized Kerberos we can call the appropriate shortcut (afslog or aklog).
#
# One last note:  the quoting in here is unsafe.  It seems that bash (at least
# 2.0[0-2]) mishandles nesting of doublequotes inside $().
#
# (late update:  krb5 userspace is less than useful; spiked.)
#

case "x$_BSA_STUPIDSHELLHACK" in
x) _BSA_STUPIDSHELLHACK=1 # and continue
#/usr/athena/bin/klist -T; /usr/heimdal/bin/klist

###############################################################################
# Prerequisites

# futz Ian and his "uids are obsolete, use gids for everything instead"...
umask 022

# acquire a path to a program somehow
if [ "x$ZSH_NAME" != x ]; then
    pathto() {
	whence -p "$1"
    }
elif [ "x$BASH" != x ]; then
    pathto() {
	type -p "$1"
    }
elif (command -v echo) >/dev/null 2>&1 &&
     command -v echo | grep / >/dev/null; then
    pathto() {
	command -v "$1"
    }
elif (whence -p echo) >/dev/null 2>&1 &&
     whence -p echo | grep / >/dev/null; then
    pathto() {
	whence -p "$1"
    }
else
    pathto() {
	# iffy...
	type "$1" | sed -e 's/^[^ ][^ ]* is hashed (\(.*\))$/\1/' \
			-e "s/^\\([^ ][^ ]*\\) is [^/]*\$/'\\1'/" \
			-e 's/^[^ ][^ ]* is //'
    }
fi

# root gets screwed... and so do zsh users
_fixpath() {
    _quietyinz=1
    eval "$(/bin/grep '^[A-Za-z_]*PATH=' $HOME/.bsa-common 2>/dev/null ||
	    /usr/bin/grep '^[A-Za-z_]*PATH=' $HOME/.bsa-common 2>/dev/null)"
    # @@@ should export all PATHs received above
    export PATH
    # ugh
    # double ugh:  /bin/pwd is somehow getting the logical path on OSX
    if [ "x$(pwd -P 2>&1 >/dev/null)" = x ]; then
	_pwdp='pwd -P'
    else
	_pwdp='\pwd'
    fi
    npath=
    oIFS="$IFS"
    IFS=:
    for dir in $PATH; do
	IFS="$oIFS"
	test -d "$dir" || continue
	dir="$(builtin cd "$dir"; eval "$_pwdp")" || continue
	case "x$npath" in
	x"$dir") ;;
	x"$dir":*) ;;
	*:"$dir":*) ;;
	*:"$dir") ;;
	*) npath=${npath:+"$npath:"}"$dir" ;;
	esac
    done
    IFS="$oIFS"
    test -n "$npath" && PATH="$npath"
    export PATH
    # hgu
    # any others?
    unset _quietyinz
}
_fixpath

# bash 2.01 cores when presented with "trap ... 0"
case "x$BASH_VERSION" in
x2.01*)
    go=0
    ;;
*)
    go=1
esac
if [ "x$KCLEANUP" = x0 ]; then
    go=0
    KCLEANUP=$$
elif [ "x$KCLEANUP" = x$$ ]; then
    :
else
    unset KCLEANUP
fi
exeunt=:

# sh requires ${1+"$@"} for 0 or more args.  ksh and bash do $@ right, but
# bash makes a complete hash of the sh version.  duuuuuuh...
if [ x$BASH = x ]; then
    args='${1+"$@"}'
elif [ "x$ZSH_NAME" = x ]; then
    args='"$@"'
else
    args='"${(@)*}"'
fi

###############################################################################
# Find out what kind of authentication we need

afs=
_my_klog=
_my_unlog=
_my_tokens=

krb=0
_my_kinit=
_my_kinit_opts=
_my_kauth=
_my_kauth_opts=
_my_ksu=
_my_kdestroy=
_my_klist=

_ktype=unknown

if [ "x${_BSA_NO_KRBAFS:+x}" = x ]; then

case "x${_BSA_DO_KRBAFS:+i}$-" in
*i*)
    # from most to least inclusive
    if type verify_krb5_conf >/dev/null 2>&1; then
	# Heimdal (KTH Kerberos 5)
	krb=5
	_ktype=heimdal
	_my_kauth=$(dirname $(pathto verify_krb5_conf))/kinit
	_my_kauth_opts='--524init --forwardable'
	_my_kinit_opts='--524init --forwardable'
	if type ssh >/dev/null 2>&1; then
	    # ssh being v4 only in most cases, and its forwarding falls apart
	    # when the forwarded tickets have addresses
	    _ktype="${_ktype}+ssh"
	    # @@@ may be --noaddresses in some versions
	    _my_kauth_opts="$_my_kauth_opts --no-addresses"
	    _my_kinit_opts="$_my_kinit_opts --no-addresses"
	fi
	pth=$(dirname $_my_kauth)
	if test -x $pth/aklog; then
	    # ...with AFS
	    _ktype="${_ktype}+afs/aklog"
	    afs=aklog
	    # this is a sop to ssh, which loses its ability to forward v4
	    # tickets if they are generated from v5 tickets with addresses
	    _my_kauth_opts="$_my_kauth_opts --afslog"
	elif test -x $pth/cklog; then
	    _ktype="${_ktype}+afs/cklog"
	    afs=cklog
	    _my_kauth_opts="$_my_kauth_opts --afslog"
	elif test -x $pth/afslog; then
	    _ktype="${_ktype}+afs/afslog"
	    afs=afslog
	    _my_kauth_opts="$_my_kauth_opts --afslog"
        elif type aklog >/dev/null 2>&1; then
	    _ktype="${_ktype}+afs/aklog-path"
	    afs=aklog
	    _my_kauth_opts="$_my_kauth_opts --afslog"
	fi
	if test -x $pth/kinit && test -x $pth/kdestroy; then
	    _my_kinit=$pth/kinit
	    _my_kdestroy=$pth/kdestroy
	    _my_klist=$pth/klist
	    # argh!  couldn't they have stayed compatible with MIT krb5?
	    _my_klist_test=-t
	    if test -x $pth/su; then
		_my_ksu=$pth/su
	    fi
	else
	    krb=0
	    afs=
	    _my_kauth=
	    _my_kauth_opts=
	    _my_kinit_opts=
	    _ktype=unknown
	    _knot="${_knot+$knot,}heimdal"
	fi
    fi
    if [ $krb = 0 ] && type ksu >/dev/null 2>&1; then
	# MIT Kerberos 5
	krb=5
	_ktype=mit5
	_my_ksu=$(pathto ksu)
	_my_kauth=$(pathto kinit)	# Krb5 kinit is more like kauth
	pth=$(dirname $_my_ksu)
	if test -x $pth/aklog; then
	    # ...with AFS
	    _ktype="${_ktype}+afs/aklog"
	    afs=aklog
	elif test -x $pth/cklog; then
	    _ktype="${_ktype}+afs/cklog"
	    afs=cklog
        elif type aklog >/dev/null 2>&1; then
	    _ktype="${_ktype}+afs/aklog-path"
	    afs=aklog
	fi
	if test -x $pth/kinit && test -x $pth/kdestroy; then
	    _my_kinit=$pth/kinit
	    _my_kdestroy=$pth/kdestroy
	    _my_klist=$pth/klist
	    _my_klist_test=-s
	else
	    krb=0
	    _my_su=
	    afs=
	    _ktype=unknown
	    _knot="${_knot+$knot,}mit5"
	fi
    fi
    if [ $krb = 0 ] && {
            test -d /System/Library/CoreServices/Kerberos.app ||
            test -d /System/Library/Frameworks/Kerberos.framework
        }; then
	# Mac OS X
	# @@@ should also handle Darwin, I suppose
	krb=5
	_ktype=osx
	_my_ksu=
	_my_kauth=$(pathto kinit)	# Krb5 kinit is more like kauth
	if type aklog >/dev/null 2>&1; then
	    # ...with AFS
	    _ktype="${_ktype}+afs/aklog"
	    afs=aklog
	fi
	_my_kinit=$(pathto kinit)
	_my_kdestroy=$(pathto kdestroy)
	_my_klist=$(pathto klist)
	_my_klist_test=-s
    fi
    if [ $krb = 0 ] && type kauth >/dev/null 2>&1; then
	krb=4
	_ktype=krb4
	_my_kauth=$(pathto kauth)
	_my_ksu=
	pth=$(dirname $_my_kauth)
	if test -x $pth/aklog; then
	    _ktype="${_ktype}+afs/aklog"
	    afs=aklog
	elif test -x $pth/cklog; then
	    _ktype="${_ktype}+afs/cklog"
	    afs=cklog
	elif test -x $pth/afslog; then
	    _ktype="${_ktype}+afs/afslog"
	    afs=afslog
	elif type aklog >/dev/null 2>&1; then
	    # separate aklog, i.e. Andrew
	    _ktype="${_ktype}+afs/ind.aklog"
	    afs=aklog
	fi
	if test -x $pth/kinit && test -x $pth/kdestroy; then
	    _my_kinit=$pth/kinit
	    _my_kdestroy=$pth/kdestroy
	    _my_klist=$pth/klist
	    if test -x $pth/su; then
		_my_ksu=$pth/su
	    fi
	else
	    krb=0
	    afs=
	    _my_kauth=
	    _ktype=unknown
	    _knot="${_knot+$knot,}krb4"
	fi
    fi
    if [ $krb = 0 ] && type klog.krb >/dev/null 2>&1; then
	krb=4
	_ktype=klog.krb
	afs=klog.krb
	_my_kinit=$(pathto klog.krb)
	_my_kauth=
	_my_ksu=
	_my_kdestroy=$(dirname $_my_kinit)/unlog.krb
	_my_klist=$(dirname $_my_kinit)/tokens.krb
	_my_klog=$_my_kinit
	_my_unlog=$_my_kdestroy
	_my_tokens=$_my_klist
    fi
    if [ x$afs = x ] && type klog >/dev/null 2>&1; then
	afs=klog
	# Kerberos isn't integrated, so we don't want it.
	# @@@ we don't know this; Andrew & SCS klog -> klog.krb and OpenAFS
	# @@@ is likely to make that the default at some point
	krb=0
	_ktype=afsonly
	_my_kauth=
	_my_kinit=
	_my_ksu=
	_my_kdestroy=
	_my_klist=
	_my_klog=$(pathto klog)
	_my_unlog=$(dirname $_my_klog)/unlog
	# this allows KTH to override... allows an optimization later
	[ "x$_my_tokens" = x ] && _my_tokens=$(dirname $_my_klog)/tokens
    fi
    if [ x$_my_klog = x ] && type klog >/dev/null 2>&1; then
	if [ x$afs = x ]; then
	    afs=klog
	fi
	_my_klog=$(pathto klog)
	_my_unlog=$(dirname $_my_klog)/unlog
	[ "x$_my_tokens" = x ] && _my_tokens=$(dirname $_my_klog)/tokens
    fi
    if [ x$afs = x ] && [ $krb = 0 ] && type kinit >/dev/null 2>&1; then
	krb=4
	_ktype="k4only"
	_my_kinit=$(pathto kinit)
	_my_kauth=
	_my_ksu=
	_my_kdestroy=$(dirname $_my_kinit)/kdestroy
	_my_klist=$(dirname $_my_kinit)/klist
    fi

    # if we don't have a running AFS cache manager, there's no point in AFS
    if [ x$afs != x ] && type netstat >/dev/null 2>&1; then
	if netstat -an 2>/dev/null |
	   egrep ' (\*|0\.0\.0\.0)[.:](7001|4711) ' >/dev/null; then
	    :
    	else
	    afs=
	    _knot="${_knot+$_knot,}no-afsd"
	fi
    fi

    # if we have a no-Kerberos semaphore, stop trying
    if test -f $HOME/.nokerb; then
	krb=0
	_knot="${_knot+$_knot,}.nokerb"
	# leave _ktype as is
    fi

    # sometimes the krb/afs stuff is a different username...
    case "x$_BSA_KRBAFS_ID" in
    x)
        ;;
    *)
        _my_kinit_opts="$_my_kinit_opts $_BSA_KRBAFS_ID"
        ;;
    esac

    # Bypass if we can't reach anything useful
    # @@@ do this better
    # *whimper*
    pusage="`ping --usage 2>&1`"
    case "$pusage" in
    *"[-t timeout]"*)
	pargs="-t 2 -c 1 -q"
	ptail=
	;;
    *"[timeout]")
	pargs=
	ptail=2
	;;
    *)
	# aieee
	pargs="-c 1 -q"
	ptail=
	;;
    esac
    if ping $pargs 128.2.129.20 $ptail >/dev/null 2>&1; then
	:
    else
	krb=0
	afs=
	_knot="${_knot+$_knot,}noping"
    fi
    unset pargs ptail

    # needed a few times
    uid="`id | sed -n 's/^uid=\([^( ][^( ]*\)[( ].*$/\1/p'`"

    # if we don't have a Kerberos realm, there's no point in Kerberos
    # also, find out the name of the current ticket cache
    # @@@ need to get and track krb4 and krb5 separately...
    if [ $krb = 4 ] && [ x$afs = xklog.krb ]; then
	if test -f /usr/vice/etc/ThisCell &&
	   [ "x$(sed 1q /usr/vice/etc/ThisCell)" != x ]; then
	    if [ x$KRBTKFILE = x ]; then
		if test -w /ticket; then
		    KRBTKFILE=/ticket/tkt$uid
		else
		    KRBTKFILE=/tmp/tkt$uid
		fi
	    fi
	    kcache="$KRBTKFILE"
	    kcname=KRBTKFILE
	    kcpfx=
	    kcvar=_BSA_KTCORE
	else
	    krb=0
	    _knot="${_knot+$_knot,}klog.krb/noconfig"
	fi
    elif [ $krb = 4 ]; then
	if test -f /etc/krb.conf &&
	   test -f /etc/krb.realms &&
	   [ "x$(sed 1q /etc/krb.conf)" != x ]; then
	    if [ x$KRBTKFILE = x ]; then
		KRBTKFILE=$($_my_klist 2>/dev/null |
			    sed -n 's/^Ticket file:	//p')
	    fi
	    kcache="$KRBTKFILE"
	    kcname=KRBTKFILE
	    kcpfx=
	    kcvar=_BSA_KTCORE
	else
	    krb=0
	    _knot="${_knot+$_knot,}krb4/noconfig"
	fi
    elif [ $krb = 5 ]; then
	if test -f /etc/krb5.conf && test -f /etc/krb5.keytab; then
	    if [ "x$KRB5CCNAME" = x ]; then
		KRB5CCNAME=$($_my_klist 2>&1 |
			     sed -n 's/^klist: .*( cache:* \(.*\)).$/\1/p')
		if [ "x$KRB5CCNAME" = x ]; then
		    # heimdal format
		    KRB5CCNAME=$($_my_klist 2>&1 |
				 sed -n 's/^klist: No .*: \([^ ][^ ]*\)$/\1/p')
		fi
		if [ "x$KRB5CCNAME" = x ]; then
		    KRB5CCNAME=FILE:/tmp/krb5cc_$uid
		fi
		# if it's missing prefix, add it so other programs don't get
		# confused (hello, aklog!)
		case "x$KRB5CCNAME" in
		x*:*)
		    ;;
		*)
		    KRB5CCNAME="FILE:$KRB5CCNAME"
		    ;;
		esac
		# NB:  the trailing dot in the regexp matches \r...
	    fi
	    # gack
	    case "x$KRB5CCNAME" in
	    *:*)
		kcache="${KRB5CCNAME#*:}"
		kcpfx="${KRB5CCNAME%:*}":
		;;
	    *)
		kcache="$KRB5CCNAME"
		kcpfx=FILE:
		;;
	    esac
	    kcname=KRB5CCNAME
	    kcvar=_BSA_KTCORE5
	    if test -f /etc/krb.conf &&
	       test -f /etc/krb.realms &&
	       [ "x$(sed 1q /etc/krb.conf)" != x ]; then
		if [ x$KRBTKFILE = x ]; then
		    KRBTKFILE=$($_my_klist 2>/dev/null |
				sed -n 's/^Ticket file:	//p')
		fi
		kcache2="$KRBTKFILE"
		kcname2=KRBTKFILE
		kcpfx2=
		kcvar2=_BSA_KTCORE
	    fi
	elif test -f /Library/Preferences/edu.mit.Kerberos; then
	    if [ "x$KRB5CCNAME" = x ]; then
		KRB5CCNAME=$($_my_klist 2>&1 |
			     sed -n 's/^Kerberos 5 .* cache:* \(.*\).$/\1/p')
		if [ "x$KRB5CCNAME" = x ]; then
		    KRB5CCNAME=FILE:/tmp/krb5cc_$uid
		fi
		# NB:  the trailing dot in the regexp matches \r...
	    fi
	    # gack
	    case "x$KRB5CCNAME" in
	    *:*)
		kcache="${KRB5CCNAME#*:}"
		kcpfx="${KRB5CCNAME%:*}":
		;;
	    *)
		kcache="$KRB5CCNAME"
		kcpfx=FILE:
		;;
	    esac
	    kcname=KRB5CCNAME
	    kcvar=_BSA_KTCORE5
	    KRBTKFILE=$($_my_klist 2>/dev/null |
			sed -n 's/^Kerberos 4 .* cache:* \(.*\).$/\1/p')
	    if [ "x$KRBTKFILE" = x ]; then
		KRBTKFILE=/tmp/tkt$uid
	    fi
	    kcache2="$KRBTKFILE"
	    kcname2=KRBTKFILE
	    kcpfx2=
	    kcvar2=_BSA_KTCORE
	else
	    # should also test for default realm, but we'd need a parser :-(
	    krb=0
	    _knot="${_knot+$_knot,}krb5/noconfig"
	fi
    fi

#    # if tickets are expired, kill them.  (leftovers, presumably)
#    if [ $krb != 0 ] && test -f $kcache; then
#	if [ $krb = 5 ] && $_my_klist $_my_klist_test >/dev/null 2>&1; then
#	    :
#	elif [ $krb = 4 ] && $_my_klist -t >/dev/null 2>&1; then
#	    :
#	else
#	    $_my_kdestroy >/dev/null 2>&1
#	fi
#    fi

    # try to make sure we aren't using a per-uid ticket cache.
    # @@ might be risky
    case "${kcpfx}x$kcache" in
    FILEx*[^0-9]$uid)
	mv "$kcache" "${kcache}_$$" >/dev/null 2>&1
	kcache="${kcache}_$$"
	eval $kcname=\"\$kcpfx\$kcache\"
	eval export $kcname
	;;
    esac
    case "x$kcname2" in
    *[^0-9]$uid)
	mv "$kcache2" "${kcache2}_$$" >/dev/null 2>&1
	kcache2="${kcache2}_$$"
	eval $kcname2=\"\$kcpfx2$kcache2\"
	eval export $kcname2
	;;
    esac

    eval "__core=\$$kcvar"
    eval "__core2=\$$kcvar2"

    if test -t 0 && test -t 1 && test -t 2; then
        # evil hack ahoy... modern desktops treat each window as a new
        # login.  (this includes X11 desktop environments and OS X)
        # so the core stuff gets somewhat evil, because we can't do it
        # properly during setup.  yes, this means GUI stuff is even more
        # screwed than usual; on the other hand, that may be for the best
        # since you really do not want it to get a whiff of non-stock
        # credentials
        if [ "x$kcache" = x ]; then
            :
        elif test -f "$kcache"; then
            :
        elif test -f "$__core"; then
            :
        else
            # we seem to have a default and should treat it as the core
#            echo evasive!
            __core="$kcache"
            eval export $kcname='"$kcache"'
            cp "$kcache" "${kcache}_$$"
            kcache="${kcache}_$$"
        fi

	if [ "x$kcache" = x ]; then
	    :
	else
	    test -f "$kcache"
	    kcf="($?)"
	fi
#	echo "[afs=$afs krb=$krb kcache=$kcache$kcf kcname=$kcname kcpfx=$kcpfx corename=$kcvar core=$__core kcache2=$kcache2 kcname2=$kcname2 kcpfx2=$kcpfx2 corename2=$kcvar2 core2=$__core2 kinit=$_my_kinit ktype=\"$_ktype\" knot=$_knot]"
    fi

    # now we know what we have to work with.  so what do we start out with?
    if [ x$_my_kinit != x ]; then
	# save bootstrap cache
	case "x$kcpfx" in
	x | xFILE:)
	    if [ "x$__core" = x ] &&
	       [ "x$kcache" != x ]; then
		if test -f "$kcache"; then
		    :
		else
		    # bootstrap login
		    echo "Bootstrap 1"
		    if test -t 0; then
			while :; do $_my_kinit $_my_kinit_opts && break; done
		    fi
		    exeunt=$_my_kdestroy
		fi
		eval "$kcvar=\"${kcpfx}${kcache}_core$$\""
		export "$kcvar"
		__core="${kcache}_core$$"
		cp "$kcache" "${kcache}_core$$"
		# now we need to acquire our own cache!
		kcache="${kcache}_$$"
		# this should work without the eval and backslashes, but some
		# shells are *really* stupid.
		eval "$kcname=\"$kcpfx\$kcache\" export $kcname"
	    fi
	    ;;
	esac
	if [ "x$kcvar2" != x ] &&
	   [ "x$__core2" = x ] &&
	   [ "x$kcache2" != x ] &&
	   [ "x$kcname2" != x ]; then
	    # now do the same with the secondary if it's defined
	    eval "$kcvar2=\"${kcpfx2}${kcache2}_core$$\""
	    export "$kcvar2"
	    __core2="${kcache2}_core$$"
	    mv "$kcache2" "${kcache2}_core$$"
	    kcache2="${kcache2}_$$"
	    eval "$kcname2=\"$kcpfx2\$kcache2\" export $kcname2"
	fi
	# load ticket cache from bootstrap cache, if we can
	if [ "x$__core" != x ] &&
	   [ "x$kcache" != x ] &&
	   test -f "$__core" &&
	   test ! -f "$kcache"; then
	    cp "$__core" "$kcache"
	    exeunt="$_my_kdestroy"
	fi
	if [ "x$__core2" != x ] &&
	   [ "x$kcache2" != x ] &&
	   test -f "$__core2" &&
	   test ! -f "$kcache2"; then
	    cp "$__core2" "$kcache2"
	fi

	# if we couldn't, try to get us some tickets
	if [ $krb != 0 ] && [ "x$kcache" != x ] && test ! -f "$kcache"; then
	    echo "Bootstrap X: krb$krb cache=$kcache core=$__core"
	    ls -l "$kcache"
	    ls -l "$__core"
	    if test -t 0; then
		while :; do $_my_kinit $_my_kinit_opts && break; done
	    fi
	    exeunt="$_my_kdestroy"
	fi
	# if we succeeded, try to make the secondary match
	if [ $krb != 0 ] && [ "x$kcache2" != x ] && test ! -f "$kcache2"; then
	    # assumption: this means MIT Kerberos
	    # @@@ API:?
	    krb524init >/dev/null 2>&1
	fi
	# if we are doing both, arrange to destroy both
	if [ $krb != 0 ] && [ "x$kcache2" != x ] && [ "x$exeunt" != x: ]; then
	    exeunt="/bin/rm -f \"$kcache2\" 2>/dev/null; $exeunt"
	fi
    fi

    # if we have AFS but don't have a token, try to get one
    if [ x$afs != x ] &&
       "$_my_tokens" 2>/dev/null |
       grep ' (AFS ID [0-9]*) tokens for ' >/dev/null; then
	:
    elif [ x$afs != x ] && [ x$_knot = x ]; then
	$afs && [ x$afs = xklog ] && exeunt=$_my_unlog
    fi
    ;;
*)  krb524init >/dev/null 2>&1 ;;
esac

# from _BSA_NO_KRBAFS
fi

###############################################################################
# Utility functions

# ls wrapper with -C, -F, and (if supported) color
# (additional "-l" below is because FreeBSD ls thinks --color == --)
if \ls --color -l >/dev/null 2>&1; then
    lscolor=--color
elif ls -G >/dev/null 2>&1; then
    lscolor=-G
else
    lscolor=
fi
if [ "x$BASH" != x ]; then
    # bash is, as usual, buggy
    _my_ls() {
	typeset args color

	if [ -t 1 ]; then args=-CF; color="$lscolor"; fi
	ls $args $color "$@"
    }
elif [ "x$ZSH_NAME" = x ]; then
    _my_ls() {
	typeset args color

	if [ -t 1 ]; then args=-CF; color="$lscolor"; fi
	ls $args $color ${1+"$@"}
    }
else
    _my_ls() {
	typeset args color

	if [ -t 1 ]; then args=-CF; color="$lscolor"; fi
	ls $args $color "${(@)*}"
    }
fi
alias ls=_my_ls

# vrel - "vos release" by pathname
if type vos > /dev/null 2>&1; then
    vrel() {
	# new gnu tail rejects historal arguments.  ancient tail rejects POSIX
	# arguments.  can't win...
	vos release `fs lq ${1-.} | (tail -n1 || tail -1) 2>/dev/null | awk '{print $1}'` -verbose
    }
fi

# wrap our magic authentication commands (except su, which we do later)
: ${_my_aklog:=aklog}
: ${_my_cklog:=cklog}
: ${_my_afslog:=afslog}
: ${_my_xkme:=xkme}
for cmd in klog unlog kinit kauth kdestroy aklog cklog afslog xkme; do
    eval "_my_${cmd}_cmd=\$_my_$cmd
	  _my_$cmd() {
	      if "\$_my_${cmd}_cmd \$_my_${cmd}_args" $args; then
		  _my_ppt
		  return 0
	      fi
	  }
	  alias $cmd=_my_$cmd"
done

# rlogin and telnet we want to wrap based on what authentication we use;
# Kerberos provides its own versions.
for cmd in rlogin telnet pagsh; do
    if [ x$_my_kinit = x ]; then
	pth=
    else
	pth=$(dirname $_my_kinit)/$cmd
	if test -x $pth; then
	    :
	else
	    pth=
	fi
    fi
    [ x$pth = x ] && pth=$(pathto $cmd)
    if [ x$pth != x ]; then
	eval "_my_${cmd}_cmd=\$pth
	      _my_$cmd() {
		  typeset rc
		  [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -A -I "\$HISTFILE"
		  "\$_my_${cmd}_cmd" $args
		  rc=\$?
		  [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -R "\$HISTFILE"
		  _my_ppt
		  return \$?
	      }
	      alias $cmd=_my_$cmd"
    fi
done

# wrapper for commands which aren't auth-specific but do thwack prompt
for cmd in trn vi vim nvi; do
    pth=$(pathto $cmd)
    if [ x$pth != x ]; then
	eval "_my_${cmd}_cmd=\$pth
	      _my_$cmd() {
		  typeset rc
		  "\$_my_${cmd}_cmd" $args
		  rc=\$?
		  _my_ppt
		  return \$?
	      }
	      alias $cmd=_my_$cmd"
    fi
done
for cmd in ssh sudo; do
    pth=$(pathto $cmd)
    if [ x$pth != x ]; then
	eval "_my_${cmd}_cmd=\$pth
	      _my_$cmd() {
		  typeset rc
		  [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -A -I "\$HISTFILE"
		  "\$_my_${cmd}_cmd" $args
		  rc=\$?
		  [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -R "\$HISTFILE"
		  _my_ppt
		  return \$?
	      }
	      alias $cmd=_my_$cmd"
    fi
done
unset cmd

# wrapper for nvi, which tweaks xterm's status line
if type nvi >/dev/null 2>&1; then
    alias vi=nvi
fi

# add a label to the prompt
psys() {
    export _BSA_PSYS="$1"
    _my_ppt
}

# pushd/popd, wrappers for bash, implementations for ksh
if [ "x$BASH" != x ]; then
    # intercept simply to force prompt-fixing
    _my_pushd() {
	pushd "$@" && _my_ppt
    }
    _my_popd() {
	popd "$@" && _my_ppt
    }
    alias pushd=_my_pushd
    alias popd=_my_popd
elif [ "x$ZSH_NAME" != x ]; then
    # intercept simply to force prompt-fixing
    _my_pushd() {
	pushd "${(@)*}" && _my_ppt
    }
    _my_popd() {
	popd "${(@)*}" && _my_ppt
    }
    alias pushd=_my_pushd
    alias popd=_my_popd
else
    pushd() {
	typeset __nwd

	# pushd [-]		- swap top two directories
	# pushd -n		  (pending)
	# pushd +n		  (pending)
	# pushd [--] ...	- push current and pass rest to cd
	if [ $# = 0 -o \( $# = 1 -a "x$1" = "x-" \) ]; then
	    __nwd="$__cwd"
	    __cwd[0]="$PWD"
	    cd "$__nwd"
	else
	    typeset -i __c
	    typeset __p
	    __p="$PWD"
	    if [ "x$1" = "x--" ]; then shift; fi
	    cd "$@" || return 1
	    __c=0
	    while [ "x${__cwd[$__c]}" != x ]; do
		__c=$(($__c+1))
	    done
	    while [ $__c -gt 0 ]; do
		__cwd[$__c]="${__cwd[$__c-1]}"
		__c=$(($__c-1))
	    done
	    __cwd[0]="$__p"
	fi
	dirs
	_my_ppt
    }

    popd() {
	typeset -i __c __d

	# popd		- pop into topmost directory
	# popd +n		- pop into Nth directory
	if [ $# = 0 ]; then
	    __c=0
	elif [ $# -gt 1 ]; then
	    echo "usage: popd [+n]" >&2
	    return 1
	else
	    case "$1" in
	    +[0-9]|+[0-9][0-9])
		__c=$(echo "x$1"|sed 's/^x+//')
		__c=$(($__c-1))
		if [ $__c -lt 0 ]; then
		    echo "popd: cannot pop negative stack index" >&2
		    return 1
		fi
		;;
	    *)
		echo "usage: popd [+n]" >&2
		return 1
		;;
	    esac
	fi
	if [ "${__cwd[$__c]}" = "" ]; then
	    echo "popd: stack underflow" >&2
	    return 1
	fi
	cd "${__cwd[$__c]}"
	__d=0
	while [ "x${__cwd[$__c+1]}" != x ]; do
	    __c=$(($__c+1))
	    __cwd[$__d]="${__cwd[$__c]}"
	    __d=$(($__d+1))
	done
	while [ $__d -le $__c ]; do
	    unset __cwd[$__d]
	    __d=$(($__d+1))
	done
	dirs
	_my_ppt
    }

    dirs() {
	print "$PWD" "${__cwd[@]}"
    }
fi

# su wrapper to fix prompt, and to prefer our own su command
if type su > /dev/null 2>&1; then
    # personal version should override the rest
    if test -x $HOME/.bin/common/su; then
	_my_su_cmd=$HOME/.bin/common/su
	exp=1
    elif test -x $HOME/.bin/su; then
	_my_su_cmd=$HOME/.bin/su
	exp=1
    elif test -x $HOME/bin/su; then
	_my_su_cmd=$HOME/bin/su
	exp=1
    elif [ x$_my_ksu != x ]; then
	_my_su_cmd=$_my_ksu
	exp=0
    else
	_my_su_cmd="$(pathto su)"
	exp=0
    fi
    if [ $exp = 1 ] && [ x$_my_ksu != x ]; then
	export _my_ksu
    fi
    unset exp
    eval "function _my_su {
	      typeset rc
	      [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -A -I "\$HISTFILE"
	      "\$_my_su_cmd" $args
	      rc=\$?
	      [ "x\$ZSH_NAME" != x ] && [ "x\$HISTFILE" != x ] && fc -R "\$HISTFILE"
	      _my_ppt
	      return \$?
	  }"
    alias su=_my_su
fi

# cd wrapper to fix prompt
if [ "x$ZSH_NAME" = x ]; then
    function _my_cd {
	if cd "$@"; then
	    _my_ppt
	    return 0
	fi
    }
else
    function _my_cd {
	if cd "${(@)*}"; then
	    _my_ppt
	    return 0
	fi
    }
fi
alias cd=_my_cd

# git wrapper to regen prompt. runs more often than needed but oh well
if [ "x$ZSH_NAME" = x ]; then
    function _my_git {
	if git "$@"; then
	    _my_ppt
	    return 0
	fi
    }
else
    function _my_git {
	if git "${(@)*}"; then
	    _my_ppt
	    return 0
	fi
    }
fi
alias git=_my_git

# regen prompt after a kswitch
if [ "x$ZSH_NAME" = x ]; then
    function _my_kswitch {
	if kswitch "$@"; then
	    _my_ppt
	    return 0
	fi
    }
else
    function _my_kswitch {
	if kswitch "${(@)*}"; then
	    _my_ppt
	    return 0
	fi
    }
fi
alias kswitch=_my_kswitch

# fg wrapper, since suspending nvi leaves us with "xterm" as the prompt
if [ "x$BASH" != x ]; then
    function _my_fg {
	# @@@ does this need to be "local" now?
	typeset rc
	builtin fg "$@"
	rc=$?
	_my_ppt
	return $?
    }
elif [ "x$ZSH_NAME" != x ]; then
    function _my_fg {
	typeset rc
	builtin fg "${(@)*}"
	rc=$?
	_my_ppt
	return $?
    }
elif (command echo) >/dev/null 2>&1; then
    function _my_fg {
	typeset rc
	command fg ${1+"$@"}
	rc=$?
	_my_ppt
	return $?
    }
else
    # this one might fail.  other suggestions?
    function _my_fg {
	typeset rc
	'fg' ${1+"$@"}
	rc=$?
	_my_ppt
	return $?
    }
fi
alias fg=_my_fg

###############################################################################
# The Dancing Prompt.  Your worst nightmare come to life :-)
# This harrowing chunk of code arranges for most significant status to end
# up either in the prompt or (for xterm-like entities) the title bar.
# (I've moved said chunk to its own file for ease of maintenance.)

case "x$-/$TERM" in
*i*/dumb)
    # may be something like tramp; avoid
    function _my_ppt { :; }
    _BSA_DOPROMPT=0
    ;;
*i*/tgtelnet)
    function _my_ppt { :; }
    # AIEEE it blows up if I set PS1 at all ?!
    #PS1="$HOST \$ "
    _BSA_DOPROMPT=0
    ;;
*i*)
    if type /usr/bin/perl > /dev/null 2>&1; then
	function _my_ppt {
            [[ "x$TERM_PROGRAM" == xApple_Terminal ]] && printf '\e]7;%s\a' "file://$HOSTNAME${PWD// /%20}"
	    eval "$(/usr/bin/perl $HOME/.prompt.pl x$BASH x$ZSH_NAME $krb x$_my_klist x$afs "x$_my_tokens" $(dirs))"
	}
    else
	unset _BSA_TTYSTR
	function _my_ppt {
            [[ "x$TERM_PROGRAM" == xApple_Terminal ]] && printf '\e]7;%s\a' "file://$HOSTNAME${PWD// /%20}"
	    typeset __i __lv __cd __d __ct __s __r __b
	    typeset -i __c

	    # This works on virtually every modern *ix and on many older ones.
	    __i="$(id | sed -e 's/^uid=\(.*\) gid=.*$/\1/' \
			    -e 's/^[0-9][0-9]*(\(.*\))$/\1/')"
	    __r="$(id | sed 's/^uid=\([0-9][0-9]*\).*$/\1/')"
	    if [ $__r = 0 ]; then
		__r='#'
	    else
		__r='$'
	    fi
	    if [ "x$BASH" != x ]; then
		__b=B
	    elif [ "x$ZSH_NAME" != x ]; then
		__b=Z
	    else
		__b=K
	    fi
	    if [ $_BSA_SH_LEVEL = 1 ]; then
		__lv=
	    else
		__lv="$_BSA_SH_LEVEL@"
	    fi
	    for __d in $(dirs); do
		if [ "x$__d" = "x$HOME" ]; then
		    __ct="~"
		elif [ "x$__d" = "x/" ]; then
		    __ct=/
		else
		    __ct="$(basename \"$__d\")"
		fi
		if [ "x$__cd" = x ]; then
		    __cd="$__ct"
		else
		    __cd="$__cd $__ct"
		fi
	    done
	    if [ "x$PSYS" = x ]; then
		__s=
	    else
		__s=" <$PSYS>"
	    fi
	    PS1="$__lv$(uname -n):! {$__i} [$__cd]$__s $__b$__r "
	    case "x$PROMPT" in
	    x)
		;;
	    *)
		PROMPT="$PS1"
		;;
	    esac
	}
    fi
    _BSA_DOPROMPT=1
    ;;
*)
    function _my_ppt { :; }
    _BSA_DOPROMPT=0
    ;;
esac

###############################################################################
# Final arrangements

if [ "x$BASH" != x ]; then
    set +o histexpand
elif [ "x$ZSH_NAME" != x ]; then
    setopt promptbang
    unset histchars
    bindkey -e
    case "x$-" in
    *i*)
	REPORTTIME=15
	HISTFILE="$HOME/.zsh_history"
	SAVEHIST=10000
	HISTSIZE=15000
	WORDCHARS='*?_-.[]~!#$%^(){}<>'	# omits / and =
	setopt printexitvalue
	setopt appendhistory autoparamkeys autoremoveslash
	setopt completeinword histignoredups ksharrays listtypes
	setopt magicequalsubst multios extendedglob
	setopt nobadpattern nonomatch
	# current zsh is braindead about ownership
	# @@@ but this is hard to fix :(
#	exeunt="chown $LOGNAME ~/.zsh_history* >&/dev/null; $exeunt"
#	exeunt="chown $LOGNAME ~/.zsh_history* ; $exeunt"
	;;
    esac
else
    set -o gmacs
fi
case "$-" in
*i*)
    let _BSA_SH_LEVEL=${_BSA_SH_LEVEL:-0}+1
    export _BSA_SH_LEVEL
    ;;
esac
_my_ppt

function pmv {
    perl -M"$1" -le "print \$$1::VERSION"
}

###############################################################################
# Cleanup

case "$-" in
*i*)
    if [ "x$exeunt" != x: ]; then
	if [ "x$go" = x1 ]; then
	    trap "$exeunt" 0
	else
	    alias exeunt "$exeunt"
	    echo "Remember to type \`exeunt' before exiting, because your shell is too dumb to do it itself."
	fi
    fi
    ;;
esac
unset go exeunt kcache kcname kcpfx args pth

# hackaround for broken aterm/wterm on freebsd
case "x$-:`uname`" in
*i*:FreeBSD)
    stty erase2 '^-'
    ;;
esac

# hack around RH forcing the prompt in /etc, dammit
if expr "x$-" : ".*i" >/dev/null && [ "x$ZSH_NAME" != x ]; then
  # gaaaack, zsh in SuSE11 doesn't do precmd right
  set -A precmd_functions ___my_precmd
  ___my_precmd() {
    typeset _dids _didp _s
    if [[ "0$_quietyinz" = 01 ]]; then
      :
    else
	    # and still more serious horkage:  the path disappears!
	    if [ "$_BSA_SHHACK" = "" ]; then
	      _BSA_SHHACK=1
	      _fixpath
	      _my_ppt
	    fi
	    if [ "x$_BSA_DOPROMPT" = x1 ] && [ "x${_BSA_STYSTR}" != x ]; then
	      echo -en "\ek"
	      echo -n "${_BSA_STYSTR}"
	      echo -en "\e\\"
	      _dids=
	    fi
	    if [ "x$_BSA_DOPROMPT" = x1 ] && [ "x${_BSA_TTYSTR}" != x ]; then
        if [ "x$STY" = x ]; then
          if [ "x$_BSA_TTYSTR1" = x ]; then
  		      _s="$_BSA_TTYSTR"
  	      else
  		      _s="$_BSA_TTYSTR1"
  	      fi
		      echo -en "\e]2;"
	      else
		      # @@@ hack for Terminal.app:  current directory
		      # (see /etc/bashrc)
		      if [ "x$TERM_PROGRAM" = xApple_Terminal ] &&
		         test -z "$INSIDE_EMACS"; then
		        echo -en "\e]7;file://"
		        echo "x$(uname -n)$PWD" | sed -e 's/^x//' -e 's/ /%20/g'
		        echo -en "\a"
		      fi
		      echo -en "\e]0;"
	      fi
	      echo -n "$_s"
	      echo -en "\a"
	      _didp=
	    fi
	    if [ "x$_BSA_DOPROMPT" = x1 ] && [ "x${_BSA_ITYSTR}" != x ]; then
	      echo -en "\e]1;"
	      echo -n "${_BSA_ITYSTR}"
	      echo -en "\a"
	      _dids=
	    fi
	    # argh, SuSE
	    unsetopt autopushd
	    unsetopt pushdtohome
	    unsetopt cdablevars
	    unsetopt correct
	    unsetopt correctall
    fi # _quietyinz
  }
  preexec() {
    if [[ "0$_quietyinz" = 01 ]]; then
      :
    else
	    typeset _b _s _t
	    if [ "x$_BSA_DOPROMPT" = x1 ] &&
	       [ "x$_BSA_STYSTR" != x ] &&
	       [ "x$STY" != x ]; then
	      _s="$_BSA_STYSTR"
	      if [ "x$_dids" = x ]; then
		      echo -en "\ek"
		      _t="$(echo "$2" | sed 's/^_my_ssh\( -.[^ ]*\)* //')"
		      echo -n "${_t%% *}"
		      echo -en "\e\\"
		      _dids=1
	      fi
	    fi
	    if [ "x$_BSA_DOPROMPT" = x1 ] && [ "x$_BSA_ITYSTR" != x ]; then
	      _s="$_BSA_ITYSTR"
	      if [ "x$_dids" = x ]; then
		      echo -en "\e]1;"
		      _t="$(echo "$2" | sed 's/^_my_ssh\( -.[^ ]*\)* //')"
		      echo -n "${_t%% *}"
		      echo -en "\a"
		      _dids=1
	      fi
	    fi
	    if [ "x$_BSA_DOPROMPT" = x1 ] && [ "x$_BSA_TTYSTR" != x ]; then
	      if [ "x$_BSA_TTYSTR1" = x ]; then
		      _s="$_BSA_TTYSTR"
	      else
		      _s="$_BSA_TTYSTR1"
	      fi
	      if [ "x$_didp" = x ]; then
		      if [ "x$STY" = x ]; then
		        echo -en "\e]2;"
		      else
		        echo -en "\e]0;"
		      fi
		      print -P -n "${_s}: [%D{%m/%d-%H:%M}] "
		      echo -n "${(j:; :V)${(f)2}}"
		      echo -en "\a"
		      _didp=1
	      fi
	    fi
    fi # _quietyinz
  }
fi

# @@@ put this block somewhere sensible
alias asfix='printf \\e\[\?47l'
fignore=(.hi)
# @@@ shell-safe this
if test -f $HOME/.rakudobrew/bin/rakudobrew; then
    p6() {
	rakudobrew exec perl6 -e "$*"
    }
    alias 6=p6
    perl6() {
	rakudobrew exec perl6 "$*"
    }
fi

# from "and continue"
;; esac
