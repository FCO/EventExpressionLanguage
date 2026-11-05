use EEL::Condition;
use EEL::IntervalIndex;
use EEL::Input;
unit class EEL::SearchIndex;

has %!entries;
has %!plans;
has %!tokens;
has %!eq;
has %!ranges;
has %!range-tokens;
has %!coercive;
has %!types;
has %!fallback;
has %!population;
has Int $!next-plan=0;
has Int $!next-token=0;
has Int $!rebalance-at=64;
has Int $.evaluated is rw = 0;
has Int $.visited is rw = 0;
has Num $!fanout = 0e0;
has Int $!samples=0;

sub signature($leaf) {
    given $leaf<kind> {
        when 'eq' { 'eq:' ~ $leaf<field>.chars ~ ':' ~ $leaf<field> ~ $leaf<key> }
        when 'type' { 'type:' ~ ($leaf<value>.DEFINITE ?? 'tag:'~$leaf<value>.Str !! 'class:'~$leaf<value>.^name) }
        default { 'range:' ~ $leaf<field> }
    }
}
method !anchor(@leaves --> Int) {
    (^@leaves.elems).list.min(-> $i {
        # Equality estimates are exact bucket populations. Range estimates
        # deliberately err high; the final predicate always confirms a hit.
        (%!population{signature(@leaves[$i])} // 0)*4 +
            ({eq=>0,range=>1,type=>2}{@leaves[$i]<kind>} // 3)
    }).Int
}
method !install(Int $plan,Int $position) {
    my $token=++$!next-token;
    my $leaf=%!plans{$plan}<leaves>[$position];
    %!plans{$plan}<token>=$token;
    %!plans{$plan}<anchor>=$position;
    %!tokens{$token}=%(|$leaf,:$plan);
    given $leaf<kind> {
        when 'eq' { (%!eq{$leaf<field>}{$leaf<key>} //= {}){$token}=True }
        when 'range' {
            (%!ranges{$leaf<field>} //= EEL::IntervalIndex.new).add($token,
                :low($leaf<low>),:high($leaf<high>),:low-open(so $leaf<low-open>),:high-open(so $leaf<high-open>));
            (%!range-tokens{$leaf<field>} //= {}){$token}=True;
            (%!coercive{$leaf<field>} //= {}){$token}=True if $leaf<coercive>;
        }
        when 'type' {
            my $key=$leaf<value>.DEFINITE ?? 'tag:'~$leaf<value>.Str !! 'class:'~$leaf<value>.^name;
            %!tokens{$token}<key>=$key;
            (%!types{$key} //= {}){$token}=True;
        }
    }
}
method !unlink(Int $token) {
    my %data=%!tokens{$token}:delete;
    given %data<kind> {
        when 'eq' {
            %!eq{%data<field>}{%data<key>}{$token}:delete;
            %!eq{%data<field>}{%data<key>}:delete unless %!eq{%data<field>}{%data<key>}.elems;
            %!eq{%data<field>}:delete unless %!eq{%data<field>}.elems;
        }
        when 'range' {
            %!ranges{%data<field>}.remove($token);
            %!range-tokens{%data<field>}{$token}:delete;
            %!coercive{%data<field>}{$token}:delete;
            %!coercive{%data<field>}:delete unless %!coercive{%data<field>}.elems;
            unless %!ranges{%data<field>}.elems { %!ranges{%data<field>}:delete; %!range-tokens{%data<field>}:delete }
        }
        when 'type' {
            %!types{%data<key>}{$token}:delete;
            %!types{%data<key>}:delete unless %!types{%data<key>}.elems;
        }
    }
}
method !rebalance {
    for %!plans.kv -> $plan,%data {
        next unless %data<leaves>.elems;
        my $position=self!anchor(%data<leaves>);
        next if $position == %data<anchor>;
        self!unlink(%data<token>);
        self!install($plan.Int,$position);
    }
    $!rebalance-at=max(64,%!entries.elems*2);
}
method add(Int $id, @plans) {
    my @registered;
    for @plans -> $original {
        my @normalized; my %ranges;
        for $original.list -> $leaf {
            if $leaf<kind> ne 'range' { @normalized.push($leaf); next }
            my $key=$leaf<field> ~ ':' ~ so $leaf<coercive>;
            unless %ranges{$key}:exists { %ranges{$key}=$leaf.Hash.clone; next }
            my %range := %ranges{$key};
            if $leaf<low> > %range<low> {
                %range<low>=$leaf<low>; %range<low-open>=so $leaf<low-open>;
            } elsif $leaf<low> == %range<low> { %range<low-open>=so (%range<low-open> || $leaf<low-open>) }
            if $leaf<high> < %range<high> {
                %range<high>=$leaf<high>; %range<high-open>=so $leaf<high-open>;
            } elsif $leaf<high> == %range<high> { %range<high-open>=so (%range<high-open> || $leaf<high-open>) }
        }
        @normalized.append(%ranges.values);
        my $plan=++$!next-plan;
        %!plans{$plan}={:$id,leaves=>@normalized.Array};
        @registered.push($plan);
        %!population{signature($_)}++ for @normalized;
        if @normalized { self!install($plan,self!anchor(@normalized)) }
        else { %!fallback{$plan}=True }
    }
    %!entries{$id}=@registered.Array;
    self!rebalance if %!entries.elems >= $!rebalance-at;
}
method remove(Int $id) {
    return unless %!entries{$id}:exists;
    for (%!entries{$id}:delete).list -> $plan {
        my %data=%!plans{$plan}:delete;
        self!unlink(%data<token>) if %data<token>:exists;
        for %data<leaves>.list -> $leaf {
            my $key=signature($leaf);
            %!population{$key}:delete if --%!population{$key} == 0;
        }
        %!fallback{$plan}:delete;
    }
    self!rebalance if $!rebalance-at > 64 && %!entries.elems < $!rebalance-at div 4;
}
method estimate($input = Nil --> Real) {
    if $input.defined {
        my $view=snapshot($input);
        my $count=%!fallback.elems;
        for %!eq.keys -> $field {
            my $cursor=$view.fields;
            if $cursor{$field}:exists { $cursor=$cursor{$field} }
            else {
                my $found=True;
                for $field.split('.') -> $part {
                    unless $cursor ~~ Associative && ($cursor{$part}:exists) { $found=False; last }
                    $cursor=$cursor{$part};
                }
                next unless $found;
            }
            my $key=scalar-key($cursor);
            $count+=(%!eq{$field}{$key} // {}).elems if $key.defined;
        }
        my %type-keys;
        if $view.fields<type>:exists {
            my $type=$view.fields<type>;
            my $name=$type.DEFINITE ?? $type.Str !! $type.^name;
            %type-keys{'tag:'~$name}=True;
            %type-keys{'class:'~$name}=True unless $view.typed;
            if !$view.typed && !$type.DEFINITE { %type-keys{'class:'~.^name}=True for $type.^mro }
        }
        if $view.typed { %type-keys{'class:'~.^name}=True for $view.object-type.^mro }
        $count+=(%!types{$_} // {}).elems for %type-keys.keys;
        my $ranges=%!range-tokens.values.map(*.elems).sum;
        $count+=$!samples ?? $ranges*$!fanout !! min(1,$ranges);
        return min(%!entries.elems,$count);
    }

    # Until sampled, use a conservative structural estimate. Wildcard plans
    # already establish a lower bound on the number of possible candidates.
    return %!entries.elems unless %!entries;
    return max(%!fallback.elems,$!fanout*%!entries.elems) if $!samples;
    %!fallback.elems + (%!entries.elems-%!fallback.elems)/max(1,%!eq.values.map(*.elems).sum+%!range-tokens.values.map(*.elems).sum+%!types.elems)
}
method candidates($input --> List) {
    my $view=snapshot($input);
    my %seen; my %ids;
    $!visited=0;
    sub hit(@tokens) {
        $!visited+=@tokens.elems;
        for @tokens -> $token {
            next if %seen{$token}++;
            %ids{%!plans{%!tokens{$token}<plan>}<id>}=True;
        }
    }
    my %fields=(|%!eq.keys,|%!ranges.keys).map({ $_=>True }).Hash;
    for %fields.keys -> $field {
        my $cursor=$view.fields;
        if $cursor{$field}:exists { $cursor=$cursor{$field} }
        else {
            my $found=True;
            for $field.split('.') -> $part {
                unless $cursor ~~ Associative && ($cursor{$part}:exists) { $found=False; last }
                $cursor=$cursor{$part};
            }
            next unless $found;
        }
        my $key=scalar-key($cursor);
        hit((%!eq{$field}{$key} // {}).keys) if $key.defined && (%!eq{$field}:exists);
        if %!ranges{$field}:exists {
            if exact($cursor) { hit(%!ranges{$field}.search($cursor)); $!visited+=%!ranges{$field}.visited }
            else {
                hit((%!coercive{$field} // {}).keys);
                if $cursor ~~ Real { hit((%!range-tokens{$field} // {}).keys.grep({ !(%!coercive{$field}{$_}:exists) })) }
            }
        }
    }
    if $view.fields<type>:exists {
        my $type=$view.fields<type>;
        my $name=$type.DEFINITE ?? $type.Str !! $type.^name;
        hit((%!types{'tag:'~$name} // {}).keys);
        hit((%!types{'class:'~$name} // {}).keys) unless $view.typed;
        if !$view.typed && !$type.DEFINITE { hit((%!types{'class:'~.^name} // {}).keys) for $type.^mro }
    }
    if $view.typed { hit((%!types{'class:'~.^name} // {}).keys) for $view.object-type.^mro }
    $!visited+=%!fallback.elems;
    %ids{%!plans{$_}<id>}=True for %!fallback.keys;
    $!evaluated=%ids.elems;
    my $ratio=%ids.elems/max(1,%!entries.elems);
    $!fanout=$!samples ?? (0.8*$!fanout+0.2*$ratio).Num !! $ratio.Num;
    $!samples++;
    %ids.keys.sort(*.Int).map(*.Int).List
}
method stats { %(entries=>%!entries.elems, plans=>%!plans.elems, tokens=>%!tokens.elems, fields=>(%!eq.elems+%!ranges.elems), type-buckets=>%!types.elems, visited=>$!visited, estimate=>self.estimate) }
method range-only { so %!ranges.elems && !%!eq.elems && !%!types.elems }
method indexable { so %!tokens.elems }
method elems { %!entries.elems }
method clear { %!entries=(); %!plans=(); %!tokens=(); %!eq=(); %!ranges=(); %!range-tokens=(); %!coercive=(); %!types=(); %!fallback=(); %!population=(); $!evaluated=0; $!visited=0; $!fanout=0e0; $!samples=0; $!rebalance-at=64 }
