#!/usr/bin/perl
# Path helper for the guards: makes paths absolute against $CWD, expands ~ and $HOME,
# collapses . and .., and (except in "exact" mode) cuts at the first glob character.
use strict; use warnings;
my $mode = shift // 'lines';
my ($home, $cwd) = ($ENV{HOME} // '', $ENV{CWD} // '/');
my %tools = map { $_ => 1 } qw(ls find fd rg grep egrep fgrep tree du mdfind locate ag ack eza exa lsd);
my %pat = map { $_ => 1 } qw(fd rg grep egrep fgrep mdfind locate ag ack);
my $cur = $cwd;    # effective folder: moved by cd and pushd inside a command
sub segments { (my $c = shift) =~ s/["']//g; return split /[;&|()`\n]+/, $c }
sub words { return grep { length } split /\s+/, shift }
sub cd_to { my @a = grep { !/^-/ } @_; $cur = absolute(@a ? $a[0] : $home, 0) }
sub absolute {
  my ($t, $cut) = @_;
  $t =~ s/["']//g;
  $t =~ s{^(?:~|\$HOME|\$\{HOME\})(?=/|$)}{$home};
  $t =~ s#/?[^/]*[*?\[{].*$## if $cut;
  $t = "$cur/$t" unless $t =~ m{^/};
  my @p;
  for (split m{/}, $t) { next if $_ eq '' || $_ eq '.'; if ($_ eq '..') { pop @p } else { push @p, $_ } }
  return '/' . join('/', @p);
}
my $in = do { local $/; <STDIN> } // '';
if ($mode eq 'lines' || $mode eq 'exact') {
  for my $l (split /\n/, $in) { print absolute($l, $mode eq 'lines'), "\n" if length $l }
} elsif ($mode eq 'tokens') {
  for my $seg (segments($in)) {
    my @w = words($seg);
    for my $t (split /[\s=]+/, $seg) {
      next if $t =~ m{^[a-z][a-z0-9+.-]*://}i;
      next unless $t =~ m{/} || $t =~ /^\.\.?$/ || $t =~ /^(?:~|\$HOME|\$\{HOME\})$/;
      print absolute($t, 1), "\n";
    }
    if (@w && $w[0] =~ /^(?:cd|pushd)$/) { shift @w; cd_to(@w) }
  }
} elsif ($mode eq 'search-roots') {
  for my $seg (segments($in)) {
    my @w = words($seg);
    shift @w while @w && $w[0] =~ /^\w+=/;
    next unless @w;
    (my $cmd = shift @w) =~ s{.*/}{};
    if ($cmd eq 'cd' || $cmd eq 'pushd') { cd_to(@w); next }
    next unless $tools{$cmd};
    my @a = grep { !/^-/ } @w;
    if ($cmd eq 'find') { my @r; for (@w) { last if /^[-!(]/; push @r, $_ } @a = @r }
    elsif ($pat{$cmd}) { @a = grep { m{/} || /^(?:\.\.?|~|\$HOME|\$\{HOME\})$/ } @a }
    print absolute($_, 1), "\n" for (@a ? @a : ('.'));
  }
} else { die "resolve-paths: unknown mode $mode\n" }
