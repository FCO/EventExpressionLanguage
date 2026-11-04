unit class EEL::InputQueue;
has @!heap;
sub before($a,$b) { $a[0] < $b[0] || ($a[0] == $b[0] && $a[1] < $b[1]) }
method push($entry) {
    @!heap.push($entry);
    my $i=@!heap.end;
    while $i > 0 {
        my $p=($i-1) div 2;
        last unless before($entry,@!heap[$p]);
        @!heap[$i]=@!heap[$p]; $i=$p;
    }
    @!heap[$i]=$entry;
}
method peek { @!heap[0] }
method shift {
    return Nil unless @!heap;
    my $out=@!heap[0]; my $tail=@!heap.pop;
    if @!heap {
        my $i=0;
        while 2*$i+1 < @!heap.elems {
            my $child=2*$i+1;
            $child++ if $child+1 < @!heap.elems && before(@!heap[$child+1],@!heap[$child]);
            last unless before(@!heap[$child],$tail);
            @!heap[$i]=@!heap[$child]; $i=$child;
        }
        @!heap[$i]=$tail;
    }
    $out
}
method elems { @!heap.elems }
method Bool { so @!heap }
method clear { @!heap=() }
