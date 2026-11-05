use nqp;
use EEL::Condition;
use EEL::IntervalIndex;
use EEL::Input;
unit class EEL::SearchIndex;

# Trie edges are NFG graphemes; suffix indexes traverse them backwards.
class PrefixTrie {
    has Bool $.backwards = False;
    has %!root = children=>{}, tokens=>{};
    has Int $.nodes is rw = 1;
    has Int $.elems is rw = 0;
    has Int $.visited is rw = 0;
    method add(Str $prefix, Int $token) {
        my $node=%!root;
        for ($!backwards ?? $prefix.comb.reverse !! $prefix.comb) -> $char {
            unless $node<children>{$char}:exists {
                $node<children>{$char}={children=>{},tokens=>{}}; $!nodes++;
            }
            $node=$node<children>{$char};
        }
        $node<tokens>{$token}=True; $!elems++;
    }
    method remove(Str $prefix, Int $token) {
        my $node=%!root; my @path;
        for ($!backwards ?? $prefix.comb.reverse !! $prefix.comb) -> $char {
            @path.push([$node,$char]); $node=$node<children>{$char};
        }
        $node<tokens>{$token}:delete; $!elems--;
        for @path.reverse -> ($parent,$char) {
            my $child=$parent<children>{$char};
            last if $child<tokens>.elems || $child<children>.elems;
            $parent<children>{$char}:delete; $!nodes--;
        }
    }
    method search(Str $value --> List) {
        my $node=%!root; my @out=$node<tokens>.keys;
        $!visited=1;
        for ($!backwards ?? $value.comb.reverse !! $value.comb) -> $char {
            last unless $node<children>{$char}:exists;
            $node=$node<children>{$char}; $!visited++;
            @out.append($node<tokens>.keys);
        }
        @out.map(*.Int).List
    }
}
has %!suffixes;
has %!suffix-tokens;
has %!prefixes;
has %!prefix-tokens;
has %!entries;
has %!plans;
has %!tokens;
has %!eq;
has %!states;
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
has Int $.intersected is rw = 0;
has Int $.pruned is rw = 0;
has Int $!intersection-trials=0;
has Int $!intersection-rejects=0;
has Num $!fanout = 0e0;
has Int $!samples=0;

sub signature($leaf) {
    given $leaf<kind> {
        when 'presence' | 'defined' { $leaf<kind> ~ ':' ~ $leaf<field> ~ ':' ~ ($leaf<value> // '') }
        when 'suffix' { 'suffix:' ~ $leaf<field>.chars ~ ':' ~ $leaf<field> ~ $leaf<value>.chars ~ ':' ~ $leaf<value> }
        when 'prefix' { 'prefix:' ~ $leaf<field>.chars ~ ':' ~ $leaf<field> ~ $leaf<value>.chars ~ ':' ~ $leaf<value> }
        when 'eq' { 'eq:' ~ $leaf<field>.chars ~ ':' ~ $leaf<field> ~ $leaf<key> }
        when 'type' { 'type:' ~ ($leaf<value>.DEFINITE ?? 'tag:'~$leaf<value>.Str !! 'class:'~$leaf<value>.^name) }
        default { 'range:' ~ $leaf<field> }
    }
}
# Range populations are estimated per field, but cached checks must include
# each bound and its openness: two subscriptions may use different intervals.
sub restriction-signature($leaf) {
    return signature($leaf) unless $leaf<kind> eq 'range';
    signature($leaf) ~ ':' ~ [$leaf<low>,$leaf<high>,so $leaf<low-open>,so $leaf<high-open>,so $leaf<coercive>].raku
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
    # Probe secondary restrictions only across fields. Same-field presence
    # adds nothing to an equality anchor. No callback or range coercion here.
    %!plans{$plan}<checks>=%!plans{$plan}<leaves>.grep({
        .<field> ne $leaf<field> && .<kind> eq any(<eq presence defined type range>)
    }).unique(:as(&restriction-signature)).map({ [restriction-signature($_), $_] }).Array;
    %!tokens{$token}=%(|$leaf,:$plan);
    given $leaf<kind> {
        when 'suffix' {
            (%!suffixes{$leaf<field>} //= PrefixTrie.new(:backwards)).add($leaf<value>,$token);
            (%!suffix-tokens{$leaf<field>} //= {}){$token}=True;
        }
        when 'prefix' {
            (%!prefixes{$leaf<field>} //= PrefixTrie.new).add($leaf<value>,$token);
            (%!prefix-tokens{$leaf<field>} //= {}){$token}=True;
        }
        when 'presence' | 'defined' {
            my $state=$leaf<kind> eq 'presence' ?? 'present' !! ($leaf<value> ?? 'defined' !! 'undefined');
            (%!states{$leaf<field>}{$state} //= {}){$token}=True;
        }
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
        when 'suffix' {
            %!suffixes{%data<field>}.remove(%data<value>,$token);
            %!suffix-tokens{%data<field>}{$token}:delete;
            unless %!suffixes{%data<field>}.elems {
                %!suffixes{%data<field>}:delete; %!suffix-tokens{%data<field>}:delete;
            }
        }
        when 'prefix' {
            %!prefixes{%data<field>}.remove(%data<value>,$token);
            %!prefix-tokens{%data<field>}{$token}:delete;
            unless %!prefixes{%data<field>}.elems {
                %!prefixes{%data<field>}:delete; %!prefix-tokens{%data<field>}:delete;
            }
        }
        when 'presence' | 'defined' {
            my $state=%data<kind> eq 'presence' ?? 'present' !! (%data<value> ?? 'defined' !! 'undefined');
            %!states{%data<field>}{$state}{$token}:delete;
            %!states{%data<field>}{$state}:delete unless %!states{%data<field>}{$state}.elems;
            %!states{%data<field>}:delete unless %!states{%data<field>}.elems;
        }
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
        for %!suffixes.keys -> $field {
            my ($found,$value)=field-value($view.fields,$field);
            next unless $found;
            $count+=$value.WHAT === Str && $value.DEFINITE
                ?? %!suffixes{$field}.search($value).elems !! %!suffix-tokens{$field}.elems;
        }
        for %!prefixes.keys -> $field {
            my ($found,$value)=field-value($view.fields,$field);
            next unless $found;
            $count+=$value.WHAT === Str && $value.DEFINITE
                ?? %!prefixes{$field}.search($value).elems !! %!prefix-tokens{$field}.elems;
        }
        for %!states.keys -> $field {
            my ($found,$value)=field-value($view.fields,$field);
            $count+=%!states{$field}.values.map(*.elems).sum if $found;
        }
        for %!eq.keys -> $field {
            my ($found,$cursor)=field-value($view.fields,$field);
            next unless $found;
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
    $!visited=0; $!intersected=0; $!pruned=0;
    my %compatible;
    my %values;
    sub compatible(Str $key,$leaf) {
        return %compatible{$key} if %compatible{$key}:exists;
        my $field=$leaf<field>;
        %values{$field} //= [field-value($view.fields,$field)];
        my ($found,$value)=%values{$field}.list;
        my $accept=$found;
        if $found {
            given $leaf<kind> {
                when 'eq' { my $scalar=scalar-key($value); $accept=$scalar.defined && $scalar eq $leaf<key> }
                when 'type' {
                    $accept=$view.typed && !$leaf<value>.DEFINITE
                        ?? so $view.object-type.^isa($leaf<value>)
                        !! type-equal($value,$leaf<value>);
                }
                when 'range' {
                    # Only compare exact CORE values here. Num, strings and
                    # custom numerics retain the original coercion/predicate.
                    if exact($value) {
                        $accept=($leaf<low-open> ?? $value > $leaf<low> !! $value >= $leaf<low>)
                            && ($leaf<high-open> ?? $value < $leaf<high> !! $value <= $leaf<high>);
                    }
                }
                when 'defined' {
                    my $safe=(Mu,Any,Bool,Int,Rat,FatRat,Num,Str).first({ nqp::eqaddr($value.WHAT,$_) }, :k).defined;
                    $accept=!$safe || (so nqp::isconcrete(nqp::decont($value))) == $leaf<value>;
                }
            }
        }
        %compatible{$key}=so $accept
    }
    # Avoid repeated secondary work on workloads where all anchors match.
    # Periodic probes let the policy recover when the input distribution changes.
    my $use-secondary=$!intersection-trials < 128
        || $!intersection-rejects*8 >= $!intersection-trials || $!samples %% 32;
    sub hit(@tokens) {
        $!visited+=@tokens.elems;
        for @tokens -> $token {
            next if %seen{$token}++;
            my $plan=%!plans{%!tokens{$token}<plan>};
            my $rejected=False;
            $!intersection-trials++ if $use-secondary && $plan<checks>.elems;
            for ($use-secondary ?? $plan<checks>.list !! ()) -> $check {
                $!intersected++;
                unless compatible($check[0],$check[1]) { $rejected=True; last }
            }
            if $rejected { $!pruned++; $!intersection-rejects++; next }
            %ids{$plan<id>}=True;
        }
    }
    for %!suffixes.keys -> $field {
        my ($found,$value)=field-value($view.fields,$field);
        next unless $found;
        if $value.WHAT === Str && $value.DEFINITE {
            hit(%!suffixes{$field}.search($value)); $!visited+=%!suffixes{$field}.visited;
        } else { hit(%!suffix-tokens{$field}.keys) }
    }
    for %!prefixes.keys -> $field {
        my ($found,$value)=field-value($view.fields,$field);
        next unless $found;
        if $value.WHAT === Str && $value.DEFINITE {
            hit(%!prefixes{$field}.search($value)); $!visited+=%!prefixes{$field}.visited;
        } else { hit(%!prefix-tokens{$field}.keys) }
    }
    for %!states.keys -> $field {
        my ($found,$value)=field-value($view.fields,$field);
        next unless $found;
        my $safe=so (Mu,Any,Bool,Int,Rat,FatRat,Num,Str).first({ nqp::eqaddr($value.WHAT,$_) }, :k).defined;
        my $defined=so nqp::isconcrete(nqp::decont($value));
        hit((%!states{$field}<present> // {}).keys);
        if $safe { hit((%!states{$field}{$defined ?? 'defined' !! 'undefined'} // {}).keys) }
        else {
            hit((%!states{$field}<defined> // {}).keys);
            hit((%!states{$field}<undefined> // {}).keys);
        }
    }
    my %fields=(|%!eq.keys,|%!ranges.keys).map({ $_=>True }).Hash;
    for %fields.keys -> $field {
        my ($found,$cursor)=field-value($view.fields,$field);
        next unless $found;
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
method stats { %(entries=>%!entries.elems, plans=>%!plans.elems, tokens=>%!tokens.elems, fields=>(|%!eq.keys,|%!ranges.keys,|%!states.keys,|%!prefixes.keys,|%!suffixes.keys).unique.elems, suffix-nodes=>%!suffixes.values.map(*.nodes).sum, prefix-nodes=>%!prefixes.values.map(*.nodes).sum, type-buckets=>%!types.elems, visited=>$!visited, intersected=>$!intersected, pruned=>$!pruned, estimate=>self.estimate) }
method range-only { so %!ranges.elems && !%!eq.elems && !%!types.elems && !%!states.elems && !%!prefixes.elems && !%!suffixes.elems }
method indexable { so %!tokens.elems }
method elems { %!entries.elems }
method clear { %!suffixes=(); %!suffix-tokens=(); %!prefixes=(); %!prefix-tokens=(); %!entries=(); %!plans=(); %!tokens=(); %!states=(); %!eq=(); %!ranges=(); %!range-tokens=(); %!coercive=(); %!types=(); %!fallback=(); %!population=(); $!evaluated=0; $!visited=0; $!intersected=0; $!pruned=0; $!intersection-trials=0; $!intersection-rejects=0; $!fanout=0e0; $!samples=0; $!rebalance-at=64 }
