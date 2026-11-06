unit class EEL::RetainedStore;
has %!entries;
has %!groups;
has %!dirty;
has %!changed;
sub groups($c) { (|$c.cut-decisions.map({ 'cut:'~.[0] }),|$c.choices.keys.map({ 'choice:'~$_ }),|$c.selections.map({ 'selection:'~.[0] })).List }
method add($c) {
    my $id=$c.result-order;
    %!entries{$id}=$c;
    %!dirty{$id}=True;
    for groups($c) -> $group { (%!groups{$group} //= {}){$id}=True; %!changed{$group}=True }
}
method remove(Int $id) {
    return unless %!entries{$id}:exists;
    my $c=%!entries{$id}:delete;
    %!dirty{$id}:delete;
    for groups($c) -> $group {
        %!groups{$group}{$id}:delete;
        %!changed{$group}=True;
        %!dirty{$_}=True for %!groups{$group}.keys;
        %!groups{$group}:delete unless %!groups{$group}.elems;
    }
}
method related($c --> List) {
    my %ids;
    for groups($c) -> $group { %ids{$_}=True for (%!groups{$group} // {}).keys }
    %ids.keys.sort(*.Int).map({ %!entries{$_} }).eager.List
}
method affect(%changes) {
    for %changes.keys -> $group { %!dirty{$_}=True for (%!groups{$group} // {}).keys }
}
method ready(--> List) {
    my @ready=%!dirty.keys.sort(*.Int).map({ %!entries{$_} }).grep(*.defined).eager;
    %!dirty=(); @ready.List
}
method schedule(@items) { %!dirty{.result-order}=True for @items.grep({ %!entries{.result-order}:exists }) }
method mark-all { %!dirty=%!entries.keys.map({ $_=>True }).Hash }
method has(Int $id --> Bool) { so %!entries{$id}:exists }
method has-group(Str $group --> Bool) { so (%!groups{$group} // {}).elems }
method changes(--> Hash) { my %changes=%!changed; %!changed=(); %changes }
method elems { %!entries.elems }
method snapshot { %!entries.keys.sort(*.Int).map({ %!entries{$_} }).eager.List }
method clear { %!entries=(); %!groups=(); %!dirty=(); %!changed=() }
