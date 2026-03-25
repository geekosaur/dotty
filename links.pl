#! /usr/bin/perl
use strict;
use warnings;

use Getopt::Long;
use Cwd qw(abs_path);

my ($dry_run, $force, $verbose) = (0, 0, 0);

GetOptions('dry-run!' => \$dry_run,
           'force!' => \$force,
           'verbose!' => \$verbose) or die;

process($dry_run, $force, $verbose);
# @@@ scan for dangling removed repo files?
exit 0;

# this is idempotent to the extent that running it twice (say,
# to deal with an unmanaged file / dir) won't cause problems.
# but if something managed was removed from the repo, nothing can be
# done here; it's too late to save it, and we key off the repo so
# won't know. a scan over $ENV{HOME} looking for dangling symlinks
# into the repo would be needed, and all we could do in that case
# would be to warn that something vanished the last time a "git pull"
# on the repo was done.
sub process {
  my ($dry, $force, $verbose, $whereami, $dir, $depth, $dots) = @_;
  $depth //= 0;
  if ($depth == 0) {
    die "not run in dotty dir" unless -d '.git' && -f 'links.pl'; 
    # $dir is relative path to the repo, for symlinking
    # $whereami is current location under . (and target under $ENV{HOME})
    $whereami = '.';
    $dots = '';
    ($dir = abs_path('.')) =~ s,^$ENV{HOME}/,, or
      die "repo must be under \$HOME for symlinks to work, sorry\n";
  }
  my $dots1 = $dots;
  $dots1 eq '' or $dots1 .= '/';
  my ($dh, $f, $mf);
  (my $whereami1 = $whereami) =~ s,^./,,;
  if ($whereami1 eq '.') {
    $whereami1 = '';
  } else {
    $whereami1 .= '/';
  }
  # recurse on dirs, preserve symlinks, symlink files with backup
  opendir $dh, $whereami or die "opendir $whereami: $!";
FILE:
  while (defined ($f = readdir $dh)) {
    if (!$depth) {
      for my $ign (qw(.git .gitignore .gitconfig links.pl LICENSE README.md)) {
        # @@@ should $verbose report these?
        next FILE if $ign eq $f;
      }
    }
    next if $f eq '.' || $f eq '..' || $f =~ /^\.#/ || $f =~ /(~|\.swp)$/;
    # directory
    if (! -l "$whereami/$f" && -d _ && ! -f "$whereami/$f/.symlink") {
      process($dry, $force, $verbose, "$whereami/$f", $dir, $depth + 1, $dots eq '' ? '..' : "$dots/..");
    }
    # not regular file, symlink, or directory with .symlink
    # .symlink will have broken stat chain, so re-stat
    elsif (! -f "$whereami/$f" && ! -d _) {
      warn "can't manage special file $whereami/$f\n";
    }
    elsif (defined ($mf = ours("$whereami/$f", $dir)) && $mf) {
      $verbose and warn "$whereami/$f already managed\n";
    }
    # exists, unmanaged
    elsif (defined $mf && !$mf) {
      # 1. should there be a --force? (is now, NYI)
      # 2. should we backup/move away and continue?
      warn "$whereami/$f already exists, skipping\n"; # @@@
    }
    # new; symlink into repo
    elsif ($dry) {
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