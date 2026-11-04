unit module EEL::Metadata;
my $lock = Lock.new;
my Int $last = 0;
my Int $sequence = 0;
sub event-id() is export {
    $lock.protect: {
        my Int $ms = (now.to-posix[0] * 1000).Int;
        if $ms <= $last { $ms = $last; $sequence++ }
        else { $sequence = (4096.rand).Int }
        if $sequence >= 4096 { $ms++; $sequence = 0 }
        $last = $ms;
        my $random = '/dev/urandom'.IO.open(:r, :bin);
        LEAVE $random.close;
        my $bytes = $random.read(8);
        die 'Cannot obtain UUID randomness' unless $bytes.elems == 8;
        my Int $tail = 0;
        $tail = ($tail +< 8) + $_ for $bytes.list;
        $tail +&= (2**62 - 1);
        my $hex = $ms.fmt('%012x') ~ '7' ~ $sequence.fmt('%03x') ~ (2**63 + $tail).fmt('%016x');
        $hex.substr(0,8) ~ '-' ~ $hex.substr(8,4) ~ '-' ~ $hex.substr(12,4) ~ '-' ~ $hex.substr(16,4) ~ '-' ~ $hex.substr(20)
    }
}
sub timestamp($value --> Instant) is export {
    return now unless $value.defined;
    return $value if $value ~~ Instant;
    return $value.Instant if $value ~~ DateTime;
    if $value ~~ Numeric {
        die 'Invalid timestamp' unless -Inf < $value < Inf;
        return Instant.from-posix($value);
    }
    DateTime.new($value.Str).Instant
}
sub metadata(%fields --> Hash) is export {
    die 'Invalid event-id' if (%fields<event-id>:exists) && !%fields<event-id>.defined;
    die 'Invalid timestamp' if (%fields<timestamp>:exists) && !%fields<timestamp>.defined;
    my $id = %fields<event-id> // event-id();
    die 'Invalid event-id: expected UUIDv7' unless $id ~~ /^ <[0..9a..fA..F]> ** 8 '-' <[0..9a..fA..F]> ** 4 '-7' <[0..9a..fA..F]> ** 3 '-' <[89aAbB]> <[0..9a..fA..F]> ** 3 '-' <[0..9a..fA..F]> ** 12 $/;
    %(timestamp => timestamp(%fields<timestamp>), event-id => $id)
}
