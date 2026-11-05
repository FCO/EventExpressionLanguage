use lib 'lib';
use Test;

# Execute the actual documented programs, not copies of their patterns.
for <objects correlation reemit strict alternatives repetition live time-window missing-close predicates proto proto-signatures proto-inheritance proto-recursive partition partition-change positional unordered ordered-choice interleave selection event-time fire-risk-2> -> $name {
    my $path = "examples/$name.raku";
    my $expected = $path.IO.lines.grep(*.starts-with('# OUTPUT: ')).map(*.substr(10)).join("\n") ~ "\n";
    my $proc = run $*EXECUTABLE, '-Ilib', $path, :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    is $proc.exitcode, 0, "$name runs";
    is $out, $expected, "$name produces documented output";
    is $err, '', "$name has no unexpected errors";
}
done-testing;
