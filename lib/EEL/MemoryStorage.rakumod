use EEL::Query;
use EEL::Input;
use EEL::SearchIndex;
use EEL::IntervalIndex;
use EEL::DeadlineQueue;
use EEL::InputQueue;
unit class EEL::MemoryStorage;

class Subscription {
    has Int $.id is required;
    has EEL::Query $.query is required;
    has $.continuation is required;
    has @.slots;
    has %.groups;
}
has %!entries;
has @!order;
has List $!snapshot-cache;
has EEL::SearchIndex $!queries .= new;
has EEL::IntervalIndex $!time .= new;
has EEL::DeadlineQueue $!deadlines .= new;
has %!slots;
has %!partitions;
has %!unpartitioned;
has %!strict;
has %!members;
has %!deadline;
has %!changed;
has EEL::InputQueue $!history-keys .= new;
has Int $!next-id=0;
has Int $!next-slot=0;
has Int $.candidates-count is rw = 0;
has Str $!strategy = 'query';
has Int $!searches = 0;
has Int $!index-visited = 0;
has Num $!temporal-fanout = 1e0;
has Bool $!reference = False;
has Bool $!simple-scan = False;
method reference(Bool $enabled = True) { $!reference=$enabled }


method register(EEL::Query:D $query, $continuation, :@waits = [], :%groups = {}, :$deadline --> Int) {
    $!snapshot-cache=List; $!simple-scan=False;
    my $id=++$!next-id;
    my @slots;
    my @descriptors=@waits.elems ?? @waits !! [{:$query}];
    for @descriptors -> %wait {
        my $slot=++$!next-slot;
        @slots.push($slot);
        %!slots{$slot}={:$id,|%wait};
        $!queries.add($slot,%wait<query>.index-plans);
        $!time.add($slot,:low(%wait<low> // -Inf),:high(%wait<high> // Inf));
        %!strict{$slot}=True if %wait<strict>;
        if %wait<partition>:exists {
            my %p=%wait<partition>;
            my $group=%p<group>;
            %!partitions{$group} //= {extract=>%p<extract>,buckets=>{},all=>{},fallback=>{}};
            %!partitions{$group}<all>{$slot}=True;
            if %p<key>.defined { (%!partitions{$group}<buckets>{%p<key>} //= {}){$slot}=True }
            else { %!partitions{$group}<fallback>{$slot}=True }
        } else { %!unpartitioned{$slot}=True }
    }
    @!order.push($id);
    %!entries{$id}=Subscription.new(:$id,:$query,:$continuation,:@slots,:%groups);
    for %groups.kv -> $kind,@keys {
        for @keys -> $key {
            $!history-keys.push([$key.Int,$id]) if $kind eq 'history' && !(%!members{$kind}{$key}:exists);
            (%!members{$kind}{$key} //= {}){$id}=True; %!changed{$kind~':'~$key}=True }
    }
    if $deadline.defined { %!deadline{$id}=$deadline; $!deadlines.add($deadline,$id) }
    $id
}
method remove(Int:D $id --> Bool) {
    return False unless %!entries{$id}:exists;
    $!snapshot-cache=List; $!simple-scan=False;
    my $entry=%!entries{$id}:delete;
    for $entry.slots -> $slot {
        my %wait=%!slots{$slot}:delete;
        $!queries.remove($slot); $!time.remove($slot);
        %!strict{$slot}:delete; %!unpartitioned{$slot}:delete;
        if %wait<partition>:exists {
            my %p=%wait<partition>;
            my $group=%p<group>;
            %!partitions{$group}<all>{$slot}:delete;
            %!partitions{$group}<fallback>{$slot}:delete;
            if %p<key>.defined {
                %!partitions{$group}<buckets>{%p<key>}{$slot}:delete;
                %!partitions{$group}<buckets>{%p<key>}:delete unless %!partitions{$group}<buckets>{%p<key>}.elems;
            }
            %!partitions{$group}:delete unless %!partitions{$group}<all>.elems;
        }
    }
    for $entry.groups.kv -> $kind,@keys {
        for @keys -> $key {
            %!changed{$kind~':'~$key}=True;
            %!members{$kind}{$key}{$id}:delete;
            %!members{$kind}{$key}:delete unless %!members{$kind}{$key}.elems;
        }
        %!members{$kind}:delete unless %!members{$kind}.elems;
    }
    %!deadline{$id}:delete;
    @!order=@!order.grep({ %!entries{$_}:exists }) if @!order.elems > 2*%!entries.elems+64;
    # Bounded tombstones: cancellation cannot grow the heap indefinitely.
    if $!deadlines.elems > 2*%!deadline.elems+64 {
        $!deadlines.clear;
        $!deadlines.add(.value,.key.Int) for %!deadline.pairs;
    }
    True
}
method snapshot(--> List) { $!snapshot-cache //= @!order.grep({ %!entries{$_}:exists }).map({ %!entries{$_} }).eager.List; $!snapshot-cache.List }
method entries(@ids --> List) { @ids.sort(*.Int).grep({ %!entries{$_}:exists }).map({ %!entries{$_} }).eager.List }
method members(Str $kind, $key --> List) { (%!members{$kind}{$key} // {}).keys.map(*.Int).List }
method has-members(Str $kind,$key --> Bool) { so (%!members{$kind}{$key} // {}).elems }
method member-keys(Str $kind --> List) { (%!members{$kind} // {}).keys.List }
method history-start {
    while $!history-keys && !self.has-members('history',$!history-keys.peek[0]) { $!history-keys.shift }
    $!history-keys ?? $!history-keys.peek[0] !! Nil
}
method expired(Real $now --> List) { self.entries($!deadlines.expired($now)) }
method candidates($event, :$raw = $event, :$time, Bool :$strict = False --> List) {
    my $view=snapshot($event);
    my $probe=(++$!searches %% 32);
    if !$time.defined && !%!partitions.elems && ($!reference || ($!simple-scan && !$probe) || !$!queries.indexable) {
        $!candidates-count=%!entries.elems;
        $!index-visited=0;
        $!strategy='route' unless $!reference;
        return self.snapshot;
    }
    $!simple-scan=False;
    my %keys;
    my %routed;
    for %!partitions.kv -> $group,%context {
        my $key=%context<extract>.($raw);
        %keys{$group}=$key;
        if $key.defined {
            %routed{$_}=True for (%context<buckets>{$key} // {}).keys;
            %routed{$_}=True for %context<fallback>.keys;
        } else { %routed{$_}=True for %context<all>.keys }
    }
    my %proposed;
    my $routed=%!unpartitioned.elems+%routed.elems;
    my $index-cost=$!queries.estimate($view)*1.5 + log(max(2,%!slots.elems));
    my $desired=$routed <= $index-cost ?? 'route' !! 'query';
    if $desired ne $!strategy {
        my $new=$desired eq 'route' ?? $routed !! $index-cost;
        my $old=$!strategy eq 'route' ?? $routed !! $index-cost;
        $!strategy=$desired if $new <= $old*0.8;
    }
    my @indexed;
    @indexed=$!queries.candidates($view) if $!strategy eq 'query' || $probe;
    $!index-visited=$!strategy eq 'query' || $probe ?? $!queries.visited !! 0;
    if $probe && $!strategy eq 'route' && $!queries.estimate($view)*1.5+log(max(2,%!slots.elems)) <= $routed*0.8 {
        $!strategy='query';
    }
    if $!reference {
        %proposed=%!slots.keys.map({ $_=>True }).Hash;
    } elsif $!strategy eq 'route' {
        if !%!partitions.elems && !$time.defined {
            $!simple-scan=$!queries.range-only;
            $!candidates-count=%!entries.elems;
            return self.snapshot;
        }
        %proposed=%routed;
        %proposed{$_}=True for %!unpartitioned.keys;
    } else {
        %proposed=@indexed.map({ $_=>True }).Hash;
        if $strict {
            %proposed{$_}=True for %routed.keys.grep({ %!strict{$_}:exists });
            %proposed{$_}=True for %!unpartitioned.keys.grep({ %!strict{$_}:exists });
        }
    }
    if !$!reference && $time.defined && %!slots.elems*$!temporal-fanout*1.5 < %proposed.elems {
        my %temporal=$!time.search($time).map({ $_=>True }).Hash;
        %proposed{$_}:delete for %proposed.keys.grep({ !(%temporal{$_}:exists) });
    }
    my $examined=%proposed.elems;
    my $in-time=0;
    my %ids;
    for %proposed.keys -> $slot {
        my %wait=%!slots{$slot};
        next if $time.defined && ($time < (%wait<low> // -Inf) || $time > (%wait<high> // Inf));
        $in-time++;
        if %wait<partition>:exists {
            my %p=%wait<partition>;
            my $key=%keys{%p<group>};
            next if $key.defined && %p<key>.defined && $key ne %p<key>;
        }
        %ids{%wait<id>}=True;
    }
    $!temporal-fanout=(0.8*$!temporal-fanout+0.2*$in-time/$examined).Num if $time.defined && $examined;
    # Temporal tree also supports arbitrary point lookups for diagnostics/tests.
    $!candidates-count=%ids.elems;
    self.entries(%ids.keys)
}
method temporal(Real $point --> List) {
    self.entries($!time.search($point).map({ %!slots{$_}<id> }).unique)
}
method search($event --> List) {
    my $view=snapshot($event);
    self.candidates($view,:raw($event)).grep({ .query.matches($view) }).eager.List
}
method changes(--> Hash) { my %changes=%!changed; %!changed=(); %changes }
method stats { %(entries=>%!entries.elems, slots=>%!slots.elems, partitions=>%!partitions.elems, temporal=>$!time.elems, deadlines=>$!deadlines.elems, query=>$!queries.stats, strategy=>$!strategy, visited=>$!index-visited) }
method elems(--> Int) { %!entries.elems }
method clear {
    $!history-keys.clear; $!snapshot-cache=List; %!entries=(); @!order=(); $!queries.clear; $!time.clear; $!deadlines.clear;
    %!slots=(); %!partitions=(); %!unpartitioned=(); %!strict=(); %!members=(); %!deadline=(); %!changed=(); $!candidates-count=0; $!strategy='query'; $!simple-scan=False; $!searches=0; $!temporal-fanout=1e0; $!index-visited=0;
}
