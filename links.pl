#! /usr/bin/perl
use strict;
use warnings;

use Cwd qw(abs_path);

process($#ARGV);
# @@@ scan for dangling removed repo files?
exit 0;

# yes, this is disgustingly quick and dirty
chomp(my $dir = `pwd`);
if (substr($dir, 0, length($ENV{HOME}) + 1) eq "$ENV{HOME}/") {
  substr($dir, 0, length($ENV{HOME}) + 1, '');
}
$dir .= '/';
print "repo = $dir\nhome = $ENV{HOME}\n";
my ($d, $f);
print "scan for additions\n";
opendir $d, '.' or die "where am i?";
FILE:
while (defined ($f = readdir $d)) {
  for (qw(. .. .git .gitignore links.pl LICENSE README.md)) {
    next FILE if $_ eq $f;
  }
  next FILE if $f =~ /^\.#/ || $f =~ /(~|\.swp)$/; # editor temp files
  if (! -e "$ENV{HOME}/$f") {
    if (@ARGV) {
      warn "symlink $f\n";
      symlink "$dir/$f", "$ENV{HOME}/$f" or die "symlink: $!";
    } else {
      print "would symlink $f\n";
    }
  }
}
closedir $d;
my $l;
print "scan for removals\n";
opendir $d, $ENV{HOME} or die "where are you?";
OLD:
while (defined ($f = readdir $d)) {
  next OLD if $f eq '.' or $f eq '..';
  if (defined ($l = readlink("$ENV{HOME}/$f")) &&
      # @@@ wrong if it's not followed by EOT or '/'!
      substr($l, 0, length($dir)) eq $dir) {
    next OLD if -e $f;
    if (@ARGV) {
      warn "remove $f symlink\n";
      unlink "$ENV{HOME}/$f" or die "unlink: $!";
    } else {
      print "would unlink $f\n";
    }
  }
  elsif (-e $f) {
    if (@ARGV == 1 && $ARGV[0] eq 'FORCE') {
      (my $bf = $f) =~ s/^\.//;
      $bf .= ".orig";
      if (-e "$ENV{HOME}/$bf") {
        die "can't back up $f to $bf";
      }
      warn "managing $f; backup at $ENV{HOME}/$bf\n";
      rename "$ENV{HOME}/$f", "$ENV{HOME}/$bf" or die "rename: $!";
      symlink "$dir$f", "$ENV{HOME}/$f" or die "symlink: $!";
    } else {
      print "$f is unmanaged\n";
    }
  }
}

# note that the old version had a somewhat confused notion of some
# invariant that it probably violated.
# this one is idempotent to the extent that running it twice (say,
# to deal with an unmanaged file / dir) won't cause problems.
# but if something managed was removed from the repo, nothing can be
# done here; it's too late to save it, and we key off the repo so
# won't know. a scan over $ENV{HOME} looking for dangling symlinks
# into the repo would be needed, and all we could do in that case
# would be to warn that something vanished the last time a "git pull"
# on the repo was done.
# @@@ should return errors
sub process {
  my ($doit, $whereami, $dir, $depth, $dots) = @_;
  $depth //= 0;
  if ($depth == 0) {
    die "not run in dotty dir" unless -d '.git' && -f 'links.pl'; 
    # $dir is relative path to the repo, for symlinking
    # $whereami is current location under . (and target under $ENV{HOME})
    $whereami = '.';
    $dots = '';
    ($dir = abs_path('.')) =~ s,^$ENV{HOME}/,,;
  }
  my $dots1 = $dots;
  $dots1 eq '' or $dots1 .= '/';
  # recurse on dirs, preserve symlinks, symlink files with backup
  my ($dh, $f, $mf);
  (my $whereami1 = $whereami) =~ s,^./,,;
  if ($whereami1 eq '.') {
    $whereami1 = '';
  } else {
    $whereami1 .= '/';
  }
  opendir $dh, $whereami or die "opendir $whereami: $!";
FILE:
  while (defined ($f = readdir $dh)) {
    if (!$depth) {
      for my $ign (qw(.git .gitignore .gitconfig links.pl LICENSE README.md)) {
        next FILE if $ign eq $f;
      }
    }
    next if $f eq '.' || $f eq '..' || $f =~ /^\.#/ || $f =~ /(~|\.swp)$/;
    # directory
    if (! -l "$whereami/$f" && -d _ && ! -f "$whereami/$f/.symlink") {
      process($doit, "$whereami/$f", $dir, $depth + 1, $dots eq '' ? '..' : "$dots/..");
    }
    # not regular file, symlink, or directory with .symlink
    # .symlink will have broken stat chain, so re-stat
    elsif (! -f "$whereami/$f" && ! -d _) {
      warn "can't manage special file $whereami/$f\n";
    }
    elsif (defined ($mf = ours("$whereami/$f", $dir)) && $mf) {
      warn "$whereami/$f already managed\n";
    }
    # exists, unmanaged
    elsif (defined $mf && !$mf) {
      # 1. should there be a --force?
      # 2. should we backup/move away and continue?
      warn "$whereami/$f already exists, skipping\n"; # @@@
    }
    # new; symlink into repo
    elsif (!$doit) {
      warn "would symlink($dots1$dir/$whereami1$f, $ENV{HOME}/$whereami1$f)\n";
    }
    else {
      warn "managing $whereami1$f\n";
      symlink "$dots1$dir/$whereami1$f", "$ENV{HOME}/$whereami1$f" or
        die "symlink $ENV{HOME}/$whereami1$f: $!";
    }
  }
}

# check if an existing symlink is ours / managed
sub ours {
  my ($tgt, $path) = @_;
  if (! -e "$ENV{HOME}/$tgt") {
    #warn "ours: new $tgt\n";
    undef; # not found
  }
  elsif (! -l "$ENV{HOME}/$tgt") { # have to repeat since above won't have used lstat
    #warn "ours: unmanaged $tgt\n";
    0; # unmanaged by definition
  }
  else {
    my $dst = readlink "$ENV{HOME}/$tgt";
    # managed iff dots then $path then opt extra / then $tgt
    $tgt =~ s,^\Q$path\E/,,;
    (my $epath = $tgt) =~ s,^./,,;
    (my $dots = $epath) =~ s,(^|/)[^/]+$,,;
    $dots eq '' or $dots .= '/';
    $dots =~ s,[^/]+,..,g; # @@@ 
    $epath =~ s,^\Q$path\E/,,;
    if ($dst =~ m,^\Q$dots\E\Q$path\E//?\Q$epath\E$,) {
      #warn "ours: managed $tgt\n";
      1;
    } else {
      #warn "ours: alien $tgt\n";
      0;
    }
  }
}