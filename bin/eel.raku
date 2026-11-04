#!/usr/bin/env raku
use lib $?FILE.IO.parent.parent.add('lib').Str;
use EEL::CLI;
my $stdout = $*OUT;
$*OUT = $*ERR;
exit run-cli(@*ARGS, :$stdout);
