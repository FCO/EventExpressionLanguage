use nqp;
use Event;
unit class EEL::State;

# One copier per fork preserves aliases and cycles among managed containers.
# Raw input (.data), closures and opaque application objects retain identity.
has %!copies;
has %!capture-copies;
has Int $.copied is rw = 0;
method copy($value) {
    return $value unless $value.defined;
    return $value if $value.WHAT === Int || $value.WHAT === Str || $value.WHAT === Rat
        || $value.WHAT === FatRat || $value.WHAT === Bool || $value.WHAT === Instant;
    my $id = nqp::objectid(nqp::decont($value)).Str;
    return %!copies{$id} if %!copies{$id}:exists;
    if $value ~~ Event {
        my $clone = $value.Mu::clone;
        %!copies{$id} = $clone; $!copied++;
        my $storage=nqp::getattr($value,Capture,'%!hash');
        my $storage-id=nqp::ishash($storage) ?? 'storage:'~nqp::objectid($storage).Str !! 'event:'~$id;
        unless %!capture-copies{$storage-id}:exists {
            my %captures;
            %!capture-copies{$storage-id}=%captures;
            for $value.hash.kv -> $key,$capture { %captures{$key}=self.copy($capture) }
        }
        $clone.EEL-captures(%!capture-copies{$storage-id});
        $clone.EEL-positions($value.list.map({ self.copy($_) }).Array);
        for $value.^attributes -> $attribute {
            next if $attribute.package === Capture;
            next if $attribute.package === Event && $attribute.name eq any('$!data', '$!storage');
            my $slot := $attribute.get_value($clone);
            my $copied = self.copy($attribute.get_value($value));
            if nqp::iscont($slot) { nqp::assign($slot, nqp::decont($copied)) }
            else { $attribute.set_value($clone, $copied) }
        }
        return $clone;
    }
    if $value ~~ Hash {
        my $clone = $value.WHAT.new;
        %!copies{$id} = $clone; $!copied++;
        for $value.kv -> $key, $item { $clone{$key} = self.copy($item) }
        return $clone;
    }
    if $value ~~ Array {
        my $clone = $value.WHAT.new;
        %!copies{$id} = $clone; $!copied++;
        $clone.push(self.copy($_)) for $value.list;
        return $clone;
    }
    if $value ~~ Map {
        my $clone := nqp::create($value.WHAT);
        my $storage := nqp::hash;
        nqp::bindattr($clone, Map, '$!storage', $storage);
        %!copies{$id} = $clone; $!copied++;
        for $value.kv -> $key, $item { nqp::bindkey($storage, $key, nqp::decont(self.copy($item))) }
        return $clone;
    }
    if $value ~~ Capture {
        my @list = $value.list.map({self.copy($_)});
        my %hash = $value.hash.map({ .key => self.copy(.value) });
        my $clone = Capture.new(:@list, :%hash);
        %!copies{$id} = $clone; $!copied++;
        return $clone;
    }
    $value
}
