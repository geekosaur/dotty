#! /usr/bin/perl
# NO LONGER compat with perl 4 or embedding! still limited to 5.8+, "thanks" deadrat
use 5.008;
use utf8;
use strict;
use warnings;
# @@@@ should check $LANG and downgrade somewhat sensibly
binmode(STDOUT, ':utf8');
my $NOMINE = $ENV{LOGNAME} || $ENV{USER} || '<who?>';
my $AKA = $ENV{_BSA_KRBAFS_ID} || $NOMINE;
$AKA =~ s/\@.*$//;

my ($bash, $zsh, $iskrb, $krb, $isafs, $afs, $lvl, $scrn, $host, $dom);
my ($cell, $tty, $uid, $eid, $kp, $ktkt, $atkt, $sh, $cmd, $git);
my ($d, $sys, $sn, $icon);
my (%hd, %un);
$bash = shift;
$zsh = shift;
$iskrb = shift;
($krb = shift) =~ s/^x//;
$isafs = shift;
($afs = shift) =~ s/^x//;
$lvl = '';
$lvl = $ENV{_BSA_SH_LEVEL} . '@' if $ENV{_BSA_SH_LEVEL} > 1;
$scrn = (defined($ENV{STY}) && $ENV{STY} ne '') ||
  (defined($ENV{TMUX}) && $ENV{TMUX} ne '');
$ktkt = '';
$atkt = '';
chop($host = `uname -n 2>/dev/null` ||
	     `hostname 2>/dev/null` ||
	     "localhost\n");
if ($host =~ /\./) {
  $dom = $host;
  $host =~ s/^([^.]+)\..*$/$1/;
} else {
  open(F, '/etc/resolv.conf');
  while (defined ($dom = <F>)) {
    chop($dom);
    last if $dom =~ s/^\s*domain\s+//i;
    last if $dom =~ s/^\s*search\s+(\S+)(\s|$)/$1/i;
  }
  close(F);
  defined $dom or $dom = '';
}
($dom =~ s/^.*(\.[^.]+\.[^.]+)$/$1/) or ($dom =~ s/^.*(\.[^.]+)$/$1/);
$dom =~ s/(\W)/\\$1/g;
# AFS has its own suffix...
if ($afs ne '') {
  if (-f '/usr/local/etc/openafs/ThisCell') {
    open(F, '/usr/local/etc/openafs/ThisCell');
  }
  elsif (-f '/var/db/openafs/etc/ThisCell') {
    open(F, '/var/db/openafs/etc/ThisCell');
  }
  elsif (-f '/etc/openafs/ThisCell') {
    open(F, '/etc/openafs/ThisCell');
  }
  elsif (-f '/usr/vice/etc/ThisCell') {
    open(F, '/usr/vice/etc/ThisCell');
  }
  elsif (-f '/usr/local/arla/etc/ThisCell') {
    open(F, '/usr/local/arla/etc/ThisCell');
  }
  elsif (-f '/usr/arla/etc/ThisCell') {
    open(F, '/usr/arla/etc/ThisCell');
  }
  else {
    open(F, '/dev/null');
  }
  chop($cell = <F>);
  close(F);
  ($cell =~ s/^.*(\.[^.]+\.[^.]+)$/$1/) or ($cell =~ s/^.*(\.[^.]+)$/$1/);
  $cell =~ s/(\W)/\\$1/g;
}
open(F, '-|') or exec '/usr/bin/tty' or exec '/bin/tty';
chop($tty = <F>);
close(F);
$tty = '' if $tty eq 'not a tty';
if ($tty ne '') {
  $tty =~ s!^.*/([^/]+)$!$1!;
  $tty =~ s/^tty//;
  $tty = '[' . substr($tty, 0, 3) . '] ';
}
{
  my @me1 = getpwuid($<);
  my @me2;
  if ($< == $>) {
    @me2 = @me1;
  } else {
    @me2 = getpwuid($>);
  }
  $hd{$<} = $me1[7];
  $hd{$>} = $me2[7];
  $un{$<} = $me1[0];
  $un{$>} = $me2[0];
}
$uid = defined($un{$<}) ? $un{$<} : $<;
$eid = defined($un{$>}) ? $un{$>} : $>;
$uid .= "/" . $eid if $eid ne $uid;
# Kerberos and/or AFS
if ($krb ne '' and $afs ne '' and $afs =~ /^$krb /) {
  $kp = $afs;
}
elsif ($krb ne '' and $afs ne '') {
  $kp = "klist -T || $afs";
}
else {
  $kp = $krb . $afs;
}
if ($kp ne '') {
  my %me;
  open(F, "($kp) 2>/dev/null |");
  # @@@@ this doesn't even try to deal with tickets/tokens outside the local
  # @@@@ realm/cell.  boo hiss.
  # @@@@ Krb5 and Krb4 identities may well be separate during the transition
  while (<F>) {
    chop;
    next unless /User(.*).s(.*) tokens for [-\w.@]+($| )/ or
		/^(P|        P|Default p)rincipal:\s+([^\@]+)\@()/ or
		/^... .. ..:..:..  ... .. ..:..:.. User(.*)s (.*)tokens /;
    if (lc(substr($1, -1, 1)) eq 'p') {
      ($ktkt = $2) =~ s/^ //;
      $ktkt = kfix($ktkt);
      $me{$ktkt} = 1;
    }
    elsif ($1 eq '' and $2 ne '') {
      ($atkt = $2) =~ s/^ \(AFS ID //;
      $atkt =~ s/\)$//;
      if (defined $un{$atkt}) {
	$atkt = $un{$atkt};
      } else {
	my $atkt2;
	open(PTS, "pts examine $atkt|");
	while (defined ($atkt2 = <PTS>)) {
	  $atkt = $1 if $atkt2 =~ /^Name: (.*), id: \d+, owner: /;
	}
	close(PTS);
      }
    }
    elsif ($1 ne '' and $ktkt eq '') {
      ($ktkt = $2) =~ s/^ (.*)'$/$1/;
      $ktkt = kfix($ktkt);
      $me{$ktkt} = 1;
    }
    elsif ($1 ne '') {
      # Kerberos ticket which we don't need to see
      my $tmp = kfix($2);
      unless (defined $me{$tmp}) {
	$ktkt .= ',' . $tmp;
	$me{$tmp} = 1;
      }
    }
    else {
      # AFS "anonymous" token
      $atkt = '<anon>';
    }
  }
  close(F);
  $ktkt = '?' if $iskrb and $krb ne '' and $ktkt eq '';
  # Heimdal's -lkafs doesn't identify its tokens, so pretend they're ours
  # (there is no good way to prove otherwise, dammit.)
  $atkt = '' if $isafs ne 'x' and $afs ne '' and $atkt eq '';
  if ($krb and $ktkt ne '' and $ktkt ne $uid) {
    $ktkt = ':' . $ktkt;
  }
  elsif ($krb and !$iskrb and $ktkt eq $uid) {
    $ktkt = ':';
  }
  else {
    $ktkt = '';
  }
  if ($afs and $atkt ne '' and $atkt ne $uid) {
    $atkt = '+' . $atkt;
  }
  elsif ($afs and $isafs eq 'x' and $atkt eq $uid) {
    $atkt = '+';
  }
  else {
    $atkt = '';
  }
  $atkt = '' if $atkt ne '' and $ktkt ne '' and substr($atkt, 1) eq substr($ktkt, 1);
  $uid = '' if $ktkt =~ m!^:?([^./]+)[./]! and $uid eq $1;
  $uid .= $atkt . $ktkt;
}
$uid = '' if $uid eq $NOMINE;
$uid .= '@' if $uid ne '';
$sh = ($bash ne 'x' ? 'B' : $zsh ne 'x' ? 'Z' : 'B') . ($> ? '$' : '#');
# @@@ this is more or less useless any more
#$cmd = $bash eq 'x' ? ':!' : ':\!';
$cmd = '';
$git = '';
my $gb = `git branch --no-color --list -vv 2>/dev/null`;
if (defined $gb and $gb ne '' and $gb =~ s/.*\* ([^\n]+).*/$1/s) {
  # note untracked branches with ?, detached with &
  # @@@ ! would be better but some shells can't escape it, it seems
  # @@@ see what a tag looks like...
  $gb =~ s/\s+[0-9a-f]{7}\s+((?:\[[^]]+\]\s)?).*$/$1/;
  $gb =~ s/\[.*\]\s+// or $gb .= '¤';
  $gb =~ s/^\(detached from (\S+)\)/$1‽/;
  # try to find out what repo we're in
  # not asking git first because we want the *local* name if possible
  my $ddd;
  chop($ddd = `pwd`);
  while ($ddd ne '') {
    # safety net @@@ git also has envars for this
    if ($ddd eq '/afs' or $ddd eq '/net') {
      $ddd = '';
      last;
    }
    if (-d "$ddd/.git") {
      last;
    }
    $ddd =~ s,/[^/]*$,,;
  }
  if ($ddd eq '') {
    # git thinks we're in a repo. could ask it...
    $ddd = '???';
  } else {
    $ddd =~ s,^.*/,,;
  }
  # also note dirty, unpushed commits
  my $gs = `git status 2>/dev/null`;
  if ($gs =~ /^Your branch is (ahead of|behind) '([^']+)' by (\d+) commits?/m) {
    if ($ddd eq '???') {
      # recovery! leaving "origin" as warning
      $ddd = $2;
    }
    # hm, colors. but that needs to be stripped for titlebar update
    if ($1 eq 'ahead of') {
      $ddd .= "⁺" . supsub($3, 0x2070);
    } else {
      $ddd .= "₋" . supsub($3, 0x2080);
    }
    if ($1 eq 'behind' and $gs !~ /can be fast-forwarded/) {
      $ddd =~ s/₋/↛/;
    }
  }
  elsif ($ddd eq '???' and $gs =~ /^Your branch is up-to-date with '([^']+)'/) {
    $ddd = $1;
  }
  if ($gs =~ /^Changes not staged for commit:$/m) {
    $ddd .= '*';
  }
  elsif ($gs =~ /^Changes to be committed:$/m) {
    $ddd .= '≻';
  }
  elsif ($gs =~ /^Untracked files:$/m) {
    $ddd .= '+';
  }
  else {
    $ddd .= ':';
  }
  $git = " «$ddd$gb»";
}
$d = ' [';
$ENV{HOME} = &kanon($ENV{HOME});
my $c = 0;
my $sp = '';
foreach (@ARGV) {
  $sp = ' ' if ++$c > 1;
  unless (defined $_ and $_ ne '') {
    warn "$c: empty path entry?";
    next;
  }
  $_ = &kanon($_);
  if ($_ eq '/') {
    $d .= $sp . '/';
  } else {
    s!^$ENV{HOME}($|/)!~$1!;
    if (m!^/!) {
      my $y;
      foreach my $x (keys %ENV) {
	next if $x eq 'PWD' or $x eq 'OLDPWD';
	next unless -d $ENV{$x};
	($y = &kanon($ENV{$x})) =~ s!([^\w/])!\\$1!g;
	if (m!^$y((/.*)?)$! and length($y) > length($x)) {
	  s!!\$$x$1!;
	  last;
	}
      }
      # we want var and one level
      # @@@ remove some useless names
      if (/^\$/) {
	1 while s!^(\$[^/]+/[^/]+/+)[^/]+/!$1/!;
	$d .= $sp . $_;
	next;
      }
    }
    if (m!^/!) {
      my $y;
      foreach my $x (keys %hd) {
	($y = $x) =~ s!(\W)!\\$1!g;
	if (m!^$y($|/)!) {
	  s!!$hd{$x}$1!;
	  last;
	}
      }
    }
    if ($_ =~ m!^/(afs|net)/!) {
      s//@/;
      if ($1 eq 'afs') {
	s!$cell($|/)!$1!o;
      } else {
	s!$dom($|/)!$1!o;
      }
      1 while s!^(@[^/]*/+)[^/]+/!$1/!;
      $d .= $sp . $_;
    } elsif (defined ($hd{$_})) {
      $d .= $sp . $hd{$_};
    } else {
      # @@@ remove some useless names
      1 while s!^(([~@][^/]*)?/+)[^/]+/!$1/!;
      $d .= $sp . $_;
    }
  }
}
$d .= ']';
if (exists $ENV{_BSA_PSYS} and $ENV{_BSA_PSYS} ne '') {
  $sys = '‹' . $ENV{_BSA_PSYS} . '› ';
} else {
  $sys = '';
}
# for xterms we save on the prompt and stow stuff
# in the titlebar.  modify for other *terms which
# allow setting the titlebar.
# @@@@ BEWARE <> breaks VTE (inappropriate Pango?)
chop($sn = `fs sysname 2>/dev/null`);
# the error is from Arla if kernel module unloaded.  sigh.
if (!defined($sn) or $sn eq 'Error detecting AFS') {
  $sn = '';
  $afs = '';
  $atkt = '';
  $uid =~ s/\+[^:]+//;
} else {
  $sn =~ s/^Current sysname (list )?is //;
  $sn =~ s/^[\`\']([^\']*\')( [\`\'][^\']*\')*/$1/;
  $sn =~ s/.$/: /;
}
$icon = '';
if ($scrn or (exists($ENV{DISPLAY}) and $ENV{TERM} =~ /(rxvt|term)([-_](\d+)?colors?)?$/)) {
  open(TTY, '> /dev/tty');
  # @@@ see at top re LANG
  binmode(TTY, ':utf8');
  # icon name
  my $did = 0;
  $icon = $host;
  if ($< == 0) {
    $icon .= '#';
    $did = 1;
  }
  # want to detect not-nominal-"me"... of course
  # this is the Directory Services Disaster in
  # yet another form...
  elsif (defined $un{$<} and $un{$<} ne $NOMINE) {
    $icon .= '*';
    $did = 1;
  }
  if ($atkt eq '?') {
    $icon .= '?';
    $did = 1;
  }
  elsif ($atkt eq 'admin' or
	 # real Kerberos
	 $ktkt =~ m![./](root|[\w-]*admin)$!) {
    $icon .= '@';
    $did = 1;
  }
  elsif ($atkt ne '' and $atkt ne '+' . $AKA) {
    $icon .= '+';
    $did = 1;
  }
  if (!$did and exists $ENV{_BSA_PSYS} and $ENV{_BSA_PSYS} ne '') {
    $icon .= '/';
  }
  $icon .= $ENV{_BSA_PSYS} if exists $ENV{_BSA_PSYS} and $ENV{_BSA_PSYS} ne '';
  if (!$scrn) {
    # icon
    print TTY "\033]1;", $icon, (exists $ENV{WINDOW} ? "[$ENV{WINDOW}]" : ''), "\007";
    # titlebar
    #print TTY "\033]0;", $sys, $sn, $uid, $host, ' ', $git, $d, "\007";
    print TTY "\033]2;", $sys, $sn, $uid, $host, ' ', $git, $d, "\007";
    # shell
    print "_BSA_TTYSTR=\047", $sys, $sn, $uid, $host, ' ', $git, $d, "\047\n";
    print "_BSA_STYSTR=\047", $icon, "\047\n";
    print "_BSA_ITYSTR=\047", $icon, "\047\n";
  } else {
    # titlebar
    if (defined($ENV{TMUX}) and $ENV{TMUX} ne '') {
	print TTY "\033]0;", $sys, $sn, $uid, $host, ' ', $git, $d, "\007";
    } else {
	print TTY "\033]0;", $sys, $sn, $uid, $host, "[$ENV{WINDOW}] ", $git, $d, "\007";
    }
    # window name
    print TTY "\033k", $icon, "\033\\";
    if (defined($ENV{TMUX}) and $ENV{TMUX} ne '') {
	print "_BSA_TTYSTR=\047", $sys, $sn, $uid, $host, ' ', $git, $d, "\047\n";
    } else {
	print "_BSA_TTYSTR=\047", $sys, $sn, $uid, $host, "[$ENV{WINDOW}] ", $git, $d, "\047\n";
    }
    print "_BSA_STYSTR=\047", $icon, "\047\n";
    print "_BSA_ITYSTR=\047", $icon, "\047\n";
  }
  close(TTY);
  $tty = '';
  $uid = '';
  $d = '';
  $sys = '';
} else {
  # bash and ksh expand ${var}s in $PS1
  # ... differently.  (AARGH!!!)
  if ($bash eq 'x') {
    $d =~ s/([\[ ])\$/$1\\\$/g;
  } else {
    $d =~ s/([\[ ])\$/$1\\\\\$/g;
  }
  print "unset _BSA_TTYSTR _BSA_STYSTR _BSA_ITYSTR\n";
}
print "PS1=\047", $tty, $lvl, $uid, $host, $cmd, $d, $sys, $git, " ", $sh, " \047\n";

sub kanon {
  # make path work
  chdir($_[0]) or return $_[0];
  chop($_[0] = `pwd`);
  $_[0];
}

sub kfix {
#print STDERR "kfix |$NOMINE|$AKA|$uid|\n";
  if ($_[0] =~ m!^(\Q$NOMINE\E|\Q$AKA\E)[./]\Q$uid\E$!) {
    '/';
  }
  elsif ($_[0] =~ m!^(\Q$NOMINE\E|\Q$AKA\E)[./](.*)$!) {
    "/$2";
  }
  else {
    $_[0];
  }
}

sub supsub {
  my $s = "$_[0]";
  my $t;
  while ($s ne '') {
    $s =~ s/^(.)//;
    $t .= chr($_[1] + ord($1) - ord('0'));
    ## @@@ gotta ditch compat...
    #if ($_[1] == 0x2070) {
    #  $t .= "\x{e2}\x{81}" . chr(0xb0 + ord($1) - ord('0'));
    #} else {
    #  $t .= "\x{e2}\x{82}" . chr(0x80 + ord($1) - ord('0'));
    #}
  }
  $t;
}
