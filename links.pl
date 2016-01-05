#! /usr/bin/perl
use strict;
use warnings;
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
      symlink "$dir/$f", "$ENV{HOME}/$f";
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
      substr($l, 0, length($dir)) eq $dir) {
    next OLD if -e $f;
    if (@ARGV) {
      warn "remove $f symlink\n";
      unlink "$ENV{HOME}/$f";
    } else {
      print "would unlink $f\n";
    }
  }
  elsif (-e $f) {
    if (@ARGV == 1 && $ARGV[0] eq 'FORCE') {
      (my $bf = $f) =~ s/^\.//;
      $f .= ".orig";
      if (-e "$ENV{HOME}/$bf") {
	die "can't back up $f to $bf";
      }
      warn "managing $f; backup at $ENV{HOME}/$bf";
      rename "$ENV{HOME}/$f", "$ENV{HOME}/$bf";
      symlink "$dir/$f", "$ENV{HOME}/$f";
    } else {
      print "$f is unmanaged\n";
    }
  }
}
