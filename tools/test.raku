#!/usr/bin/env raku
my @tests = 't'.IO.dir.grep({ .f && .extension eq 't' }).sort;
my $failures = 0;
for @tests -> $test {
    $failures++ if run($*EXECUTABLE, '-Ilib', $test.Str).exitcode;
}
exit($failures ?? 1 !! 0);
