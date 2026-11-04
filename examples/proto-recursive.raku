use lib 'lib';
use EEL;

# Um proto pode chamar sua própria família depois de consumir um evento.
event Tree {
    proto pattern node {*}
    pattern node:sym<leaf> { <leaf=.event(:type<leaf>)> }
    pattern node:sym<group> {
        <open=.event(:type<open>)>
        <child=.node>
        <close=.event(:type<close>)>
    }
    pattern TOP { :!ignore-unexpected <tree=.node> }
}
my $error;
({type=>'open'},{type=>'leaf',id=>42},{type=>'close'}).Supply.match(Tree).tap(
    -> $event {
        if $event<tree>.hash<child>:exists {
            say "group containing leaf {$event<tree><child><leaf>.id}";
        } else {
            say "leaf {$event<tree><leaf>.id}";
        }
    },
    quit => -> $failure { $error=$failure },
);
$error.throw if $error.defined;
# OUTPUT: leaf 42
# OUTPUT: group containing leaf 42
