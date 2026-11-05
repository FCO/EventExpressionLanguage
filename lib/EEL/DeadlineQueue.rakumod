unit class EEL::DeadlineQueue;
has @!heap;
method add(Real:D $deadline, Int:D $id) {
    @!heap.push([$deadline,$id]);
    my $i=@!heap.end;
    while $i > 0 {
        my $p=($i-1) div 2;
        last if @!heap[$p][0] <= $deadline;
        @!heap[$i]=@!heap[$p]; $i=$p;
    }
    @!heap[$i]=[$deadline,$id];
}
method expired(Real:D $now --> List) {
    my @out;
    while @!heap && @!heap[0][0] < $now {
        @out.push(@!heap[0][1]);
        my $tail=@!heap.pop;
        last unless @!heap;
        my $i=0;
        while 2*$i+1 < @!heap.elems {
            my $child=2*$i+1;
            $child++ if $child+1 < @!heap.elems && @!heap[$child+1][0] < @!heap[$child][0];
            last if @!heap[$child][0] >= $tail[0];
            @!heap[$i]=@!heap[$child]; $i=$child;
        }
        @!heap[$i]=$tail;
    }
    @out.List
}
method elems { @!heap.elems }
method clear { @!heap=() }
