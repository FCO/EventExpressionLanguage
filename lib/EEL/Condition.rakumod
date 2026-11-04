unit class EEL::Condition;

has Str $.kind = 'opaque';
has Str $.op = '';
has Mu $.bound;
has @.children;

method comparison(Str $op,$bound) { self.new(:kind<compare>,:$op,:$bound) }
method literal($bound) { self.new(:kind<literal>,:$bound) }
method junction(Str $kind,*@children) { self.new(:$kind,:@children) }

# Conditions emitted by the slang own evaluated bounds, never source strings.
method accepts($value, &equal --> Bool) {
    given $!kind {
        when 'compare' {
            return so do given $!op {
                when '==' { $value == $!bound }
                when '!=' { $value != $!bound }
                when '<' { $value < $!bound }
                when '<=' { $value <= $!bound }
                when '>' { $value > $!bound }
                when '>=' { $value >= $!bound }
            }
        }
        when 'literal' {
            sub member(Any $bound) {
                return $bound.accepts($value,&equal) if $bound ~~ EEL::Condition;
                return so $bound.($value) if $bound ~~ Callable:D;
                equal($value,$bound)
            }
            return so member($!bound);
        }
        when 'any' { return so @!children.first({ .accepts($value,&equal) }) }
        when 'all' { return so @!children.map({ .accepts($value,&equal) }).all }
        when 'one' { return @!children.grep({ .accepts($value,&equal) }).elems == 1 }
        when 'none' { return !@!children.first({ .accepts($value,&equal) }).defined }
        when 'not' { return !@!children[0].accepts($value,&equal) }
        default { return so $!bound.($value) if $!bound ~~ Callable:D; equal($value,$!bound) }
    }
}
sub exact($v) is export { so $v.DEFINITE && ($v.WHAT === Int || $v.WHAT === Rat || $v.WHAT === FatRat) }
sub scalar-key($v) is export {
    return Nil unless $v.WHAT === Str || $v.WHAT === Int || $v.WHAT === Rat || $v.WHAT === FatRat || $v.WHAT === Bool;
    $v.WHAT.WHICH.Str ~ ':' ~ $v.raku
}
# DNF of necessary indexable restrictions. An empty conjunction is a wildcard.
method plans(Str $field --> List) {
    given $!kind {
        when 'literal' {
            if $field eq 'type' && ($!bound ~~ Str || !$!bound.DEFINITE) {
                return ([%(kind=>'type',:$field,value=>$!bound).item],).List;
            }
            my $key=scalar-key($!bound);
            return $key.defined ?? ([%(kind=>'eq',:$field,:$key).item],).List !! ([],).List;
        }
        when 'compare' {
            return ([],).List unless exact($!bound) && $!bound != Inf && $!bound != -Inf;
            return ([],).List if $!op eq '!=';
            my %leaf=kind=>'range', :$field, low=>-Inf, high=>Inf, coercive=>True;
            given $!op {
                when '==' { %leaf<low>=$!bound; %leaf<high>=$!bound }
                when '>' | '>=' { %leaf<low>=$!bound; %leaf<low-open>=$!op eq '>' }
                when '<' | '<=' { %leaf<high>=$!bound; %leaf<high-open>=$!op eq '<' }
            }
            return ([%leaf.item],).List;
        }
        when 'any' { return @!children.map({ |.plans($field) }).List }
        when 'all' {
            my @plans = [] ,;
            for @!children -> $child {
                my @next;
                for @plans -> $left { for $child.plans($field) -> $right {
                    @next.push([|$left,|$right]); return ([],).List if @next.elems > 64;
                } }
                return ([],).List if @next.elems > 64;
                @plans=@next;
            }
            return @plans.List;
        }
        default { return ([],).List }
    }
}
