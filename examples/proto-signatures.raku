use lib 'lib';
use EEL;

# A mesma chamada escolhe o overload pela assinatura Raku.
event Reading {
    has $.value;
    proto pattern reading(|) {*}
    multi pattern reading(Int $expected, :$source = 'sensor') {
        <raw=.event: :type($source), :value($expected)>
    }
    multi pattern reading(Str $expected, :$source = 'status') {
        <raw=.event: :type($source), :value($expected)>
    }
    pattern TOP {
        [ | <reading: 42> | <reading: 'ready'> ]
        { $!value = $<reading><raw>.value }
    }
}
my $error;
({type=>'sensor',value=>42},{type=>'status',value=>'ready'}).Supply.match(Reading).tap(
    -> $event { say "reading: {$event.value}" },
    quit => -> $failure { $error=$failure },
);
$error.throw if $error.defined;
# OUTPUT: reading: 42
# OUTPUT: reading: ready
