#!/usr/bin/perl
# Splits a command from a person's session into its words, or refuses it. A command is one line: plain ASCII words,
# '...' and "..." quotes, and nothing else the shell would expand or treat as an operator. Letters, digits, marks,
# punctuation and symbols beyond ASCII may appear only inside quotes (a name or reason such as "José"); guard.sh lets
# them through only where a free text is expected. Prints the words in UTF-8, one per line after "w:" (an empty
# quoted word stays a word); on a refusal prints the reason and exits 1.
use strict; use warnings;
use Encode qw(decode FB_CROAK);
binmode STDOUT, ':encoding(UTF-8)';
my $raw = do { local $/; <STDIN> } // '';
sub no_ { print STDERR "$_[0]\n"; exit 1 }
my $c = eval { decode('UTF-8', $raw, FB_CROAK) };
no_("that command is not valid UTF-8") unless defined $c;
no_("a command is one line: newlines are refused") if $c =~ /[\n\r\x{2028}\x{2029}]/;
no_("backslashes are refused") if $c =~ /\\/;
no_("control characters, tabs included, are refused") if $c =~ /[\x00-\x1f\x7f]/;
# Beyond ASCII: no invisible, formatting, private or unassigned characters, and no spaces other than a plain one.
no_("invisible or unusual characters are refused") if $c =~ /[^\x00-\x7f\p{L}\p{M}\p{N}\p{P}\p{S}]/;
no_("that command is too long") if length($c) > 2000;
my %why = (
  '|' => 'pipes are refused', '<' => 'redirections are refused', '>' => 'redirections are refused',
  '$' => 'variables and substitutions are refused', '`' => 'command substitution is refused',
  ';' => 'one command at a time: ; and & are refused', '&' => 'one command at a time: ; and & are refused',
  '(' => 'subshells are refused', ')' => 'subshells are refused', '#' => 'comments are refused',
  '~' => 'a path starting with ~ goes inside quotes, as the skills write it', '"' => 'a quote is not closed',
  "'" => 'a quote is not closed', '=' => 'assignments are refused',
);
my (@w, $cur);
while ($c =~ /\G(?:( +)|"([^"]*)"|'([^']*)'|([A-Za-z0-9_.\/,:+-]+)|(.))/gc) {
  if (defined $1) { push @w, $cur if defined $cur; undef $cur; next }
  my $part = $2 // $3 // $4;
  if (defined $5) {
    no_("non-ASCII characters are refused outside quotes") if ord($5) > 127;
    no_($why{$5} // 'globs, braces and other shell characters are refused');
  }
  # zsh and bash still expand $ and ` inside double quotes; ! is history expansion in an interactive shell.
  no_('$, ` and ! are refused, even inside double quotes') if defined $2 && $2 =~ /[\$`!]/;
  $cur = ($cur // '') . $part;
}
push @w, $cur if defined $cur;
no_('the command is empty') unless @w;
print map { "w:$_\n" } @w;
