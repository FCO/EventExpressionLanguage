unit class EEL::IntervalIndex;

# An augmented AVL tree. Equal starts are ordered by the unique token.
class Node {
    has Real $.low is rw;
    has Real $.high is rw;
    has Bool $.low-open is rw;
    has Bool $.high-open is rw;
    has Int $.token is rw;
    has Int $.height is rw = 1;
    has Real $.maximum is rw;
    has Node $.left is rw;
    has Node $.right is rw;
}
has Node $!root;
has %!keys;
has Int $.visited is rw = 0;
sub height($n) { $n.defined ?? $n.height !! 0 }
sub maximum($n) { $n.defined ?? $n.maximum !! -Inf }
sub update($n) {
    $n.height=1+max(height($n.left),height($n.right));
    $n.maximum=max($n.high,maximum($n.left),maximum($n.right));
    $n
}
sub right($n) { my $p=$n.left; $n.left=$p.right; $p.right=update($n); update($p) }
sub left($n) { my $p=$n.right; $n.right=$p.left; $p.left=update($n); update($p) }
sub balance($n) {
    update($n);
    if height($n.left)-height($n.right) > 1 {
        $n.left=left($n.left) if height($n.left.left) < height($n.left.right);
        return right($n);
    }
    if height($n.right)-height($n.left) > 1 {
        $n.right=right($n.right) if height($n.right.right) < height($n.right.left);
        return left($n);
    }
    $n
}
sub before($low,$token,$n) { $low < $n.low || ($low == $n.low && $token < $n.token) }
sub insert($n,$item) {
    return $item unless $n.defined;
    if before($item.low,$item.token,$n) { $n.left=insert($n.left,$item) }
    else { $n.right=insert($n.right,$item) }
    balance($n)
}
sub delete($n,$low,$token) {
    return Node unless $n.defined;
    if $n.token == $token {
        return $n.right unless $n.left.defined;
        return $n.left unless $n.right.defined;
        my $next=$n.right; $next=$next.left while $next.left.defined;
        $n.low=$next.low; $n.high=$next.high; $n.low-open=$next.low-open;
        $n.high-open=$next.high-open; $n.token=$next.token;
        $n.right=delete($n.right,$next.low,$next.token);
    } elsif before($low,$token,$n) { $n.left=delete($n.left,$low,$token) }
    else { $n.right=delete($n.right,$low,$token) }
    balance($n)
}
method add(Int:D $token, Real :$low = -Inf, Real :$high = Inf, Bool :$low-open = False, Bool :$high-open = False) {
    die 'Duplicate interval token' if %!keys{$token}:exists;
    %!keys{$token}=$low;
    $!root=insert($!root,Node.new(:$token,:$low,:$high,:$low-open,:$high-open,:maximum($high)));
}
method remove(Int:D $token --> Bool) {
    return False unless %!keys{$token}:exists;
    $!root=delete($!root,%!keys{$token}:delete,$token);
    True
}
method search(Real:D $point --> List) {
    $!visited=0;
    my @found;
    sub visit($n) {
        return unless $n.defined && $n.maximum >= $point;
        $!visited++;
        visit($n.left);
        return if $n.low > $point;
        @found.push($n.token) if ($point > $n.low || !$n.low-open) && ($point < $n.high || ($point == $n.high && !$n.high-open));
        visit($n.right);
    }
    visit($!root);
    @found.List
}
method elems { %!keys.elems }
method clear { $!root=Node; %!keys=() }
