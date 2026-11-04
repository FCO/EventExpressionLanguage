use nqp;
use MetamodelX::Event;
use EEL::Slang;
use EEL::SupplyMatch;

sub EXPORT() {
    die 'EEL slang requires the Rakudo RakuAST frontend (RAKUDO_RAKUAST=1)'
        unless nqp::gethllsym('Raku', 'COMPILER-FRONTEND') eq 'rakuast';
    my $LANG := $*LANG;
    my $grammar = $LANG.slang_grammar('MAIN');
    # Keep the host entrypoint in a lexical adapter; do not mutate the base grammar.
    my $original := $grammar.HOW.find_method($grammar, 'statementlist');
    my &regular = -> Mu $cursor {
        $original ~~ Method
            ?? $original.($cursor)
            !! nqp::dispatch('boot-code', nqp::getattr($original, nqp::what($original), '$!do'), nqp::decont($cursor))
    };
    sub adapter($name) {
        my $method := $grammar.HOW.find_method($grammar, $name);
        -> Mu $cursor, |args {
            $method ~~ Method ?? $method.($cursor, |args)
                !! nqp::dispatch('boot-code', nqp::getattr($method, nqp::what($method), '$!do'), nqp::decont($cursor), |args)
        }
    }
    my &args = adapter('arglist');
    my &block = adapter('block');
    my &paren = adapter('circumfix:sym<( )>');
    my &square = adapter('circumfix:sym<[ ]>');
    my &brace = adapter('circumfix:sym<{ }>');
    # Register the HOW and syntax together. EXPORTHOW would rebuild the braid
    # after EXPORT and discard the other MAIN extensions on RakuAST.
    $LANG.set_how('event', MetamodelX::Event);
    my $actions = $LANG.slang_actions('MAIN').^mixin(EEL::Slang::Actions);
    $LANG.define_slang('MAIN', $grammar.^mixin(EEL::Slang::Grammar[&regular, &args, &block, &paren, &square, &brace]), $actions);
    Map.new
}
