#!/usr/bin/perl
require "sys/ioctl.ph";
$file = shift;
open T, ">$file" or die "$!"; 
open D, ">/tmp/X" or do { *D=*STDOUT }; 
# *T = *STDOUT;
print D "\nDEBUG::: IOCTL: ";
sub expand_escapes {
  local $_ = shift;
  s{
    (
      \\
      (?:
        x[A-Fa-f0-9]{0,2}  # hex escape
        |
        0[0-7]{0,3}        # octal escape
        |
        c.                 # ctrl-escape
        |
        ^\[.               # ascii rep escape
        |
        .                  # any other
      )
    )
  }{qq["$1"]}geexs;
  return $_;
}
do {
    print D $_ eq '\e' ? '\e' : $_,'|'; 
    ioctl(T, &TIOCSTI, $_); 
} for split "", join " ", map { expand_escapes $_ } @ARGV;
print D "\n\n";
