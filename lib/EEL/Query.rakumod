use EEL::Input;
use EEL::Condition;
unit class EEL::Query;

# A predicate over a raw event. Storage knows only this predicate and its payload.
has Map $.conditions;

submethod BUILD(:%conditions = {}) {
    my %copy;
    for %conditions.kv -> $field, $expected {
        if $expected ~~ Associative {
            for $expected.keys -> $op {
                die "Unsupported EEL query operator '$op'" unless $op eq any('==', '!=', '>', '>=', '<', '<=');
            }
            %copy{$field} = $expected.Map;
        } else {
            %copy{$field} = $expected;
        }
    }
    $!conditions = %copy.Map;
}

method matches($input --> Bool) {
    my $view = snapshot($input);
    my $event = $view.fields;
    sub equal($value, $expected, $field --> Bool) {
        return so $value eqv $expected unless $field eq 'type';
        return so $view.object-type.^isa($expected) if $view.typed && !$expected.DEFINITE;
        type-equal($value, $expected)
    }
    for $!conditions.kv -> $field, $expected {
        my ($found,$value)=field-value($event,$field);
        return False unless $found;
        sub member(Any $expected --> Bool) {
            return $expected.accepts($value, -> $a,$b { equal($a,$b,$field) }) if $expected ~~ EEL::Condition;
            return so $expected.($value) if $expected ~~ Callable:D;
            equal($value,$expected,$field)
        }
        if $expected ~~ EEL::Condition|Junction {
            return False unless so member($expected);
        } elsif $expected ~~ Callable:D {
            return False unless $expected.($value);
        } elsif $expected ~~ Associative {
            for $expected.kv -> $op, $bound {
                my $accept = do given $op {
                    when '==' { equal($value, $bound, $field) }
                    when '!=' { !equal($value, $bound, $field) }
                    default {
                        return False unless $value ~~ Real && $bound ~~ Real;
                        do given $op {
                            when '>'  { $value >  $bound }
                            when '>=' { $value >= $bound }
                            when '<'  { $value <  $bound }
                            when '<=' { $value <= $bound }
                        }
                    }
                }
                return False unless $accept;
            }
        } else {
            return False unless equal($value, $expected, $field);
        }
    }
    True
}

# Index hints are necessary conditions, never substitutes for matches().
method index-plans(--> List) {
    my @plans = [] ,;
    for $!conditions.kv -> $field,$expected {
        my @field-plans;
        if $expected ~~ EEL::Condition {
            @field-plans=$expected.plans($field);
        } elsif $field eq 'type' {
            if $expected ~~ Str || !$expected.DEFINITE {
                @field-plans = [%(kind=>'type',:$field,value=>$expected).item],;
            } else { @field-plans=[] , }
        } elsif $expected ~~ Associative {
            my @leaves;
            for $expected.kv -> $op,$value {
                if $op eq '==' {
                    my $key=scalar-key($value);
                    @leaves.push({kind=>'eq',:$field,:$key}) if $key.defined;
                } elsif $op ne '!=' && exact($value) {
                    my %leaf=kind=>'range',:$field,low=>-Inf,high=>Inf,coercive=>False;
                    if $op eq '>' || $op eq '>=' { %leaf<low>=$value; %leaf<low-open>=$op eq '>' }
                    else { %leaf<high>=$value; %leaf<high-open>=$op eq '<' }
                    @leaves.push(%leaf);
                }
            }
            @field-plans=@leaves.Array ,;
        } else {
            my $key=scalar-key($expected);
            @field-plans=$key.defined ?? ([%(kind=>'eq',:$field,:$key).item],) !! ([],);
        }
        @field-plans=@field-plans.map({ [|$_, %(kind=>'presence', :$field)] }).Array;
        my @next;
        for @plans -> $left { for @field-plans -> $right {
            @next.push([|$left,|$right]); return ([],).List if @next.elems > 64;
        } }
        return ([],).List if @next.elems > 64;
        @plans=@next;
    }
    @plans.List
}
