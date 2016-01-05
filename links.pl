#! /usr/bin/perl
# yes, this is disgustingly quick and dirty
chomp(my $dir = `pwd`);
$dir .= '/';
my ($d, $f);
opendir $d, '.' or die "where am i?";
FILE:
while ($f = readdir $d) {
  for (qw(. .. .git .gitignore links.pl LICENSE README.md)) {
    next FILE if $_ eq $f;
  }
  next if $f =~ /^\.#/ || $f =~ /(~|\.swp)$/; # editor temp files
  if (! -e "$ENV{HOME}/$f") {
    if (@ARGV) {
      warn "eventually symlink $f\n";
    } else {
      print "would symlink $f\n";
    }
  }
}
closedir $d;
my $l;
opendir $d, $ENV{HOME} or die "where are you?";
while ($f = readdir $d) {
  next if $f eq '.' or $f eq '..';
  if (defined ($l = readlink("$ENV{HOME}/$f"))) {
    next unless substr($l, 0, length $dir) eq $dir;
    next unless -e $f;
    if (@ARGV) {
      warn "eventually remove $f symlink\n";
    } else {
      print "would unlink $f\n";
    }
  }
  elsif (-e $f) {
    print "managed $f is not a symlink\n";
  }
}
