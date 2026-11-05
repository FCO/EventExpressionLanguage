use NativeCall;
unit module EEL::Clock;
class Timespec is repr('CStruct') { has long $.seconds; has long $.nanoseconds }
sub clock_gettime(int32, Timespec --> int32) is native { * }
sub monotonic(--> Int) is export {
    my $id = do given $*KERNEL.name.lc { when 'darwin' { 6 }; when 'linux' { 1 }; default { die 'Unsupported monotonic clock platform' } };
    my $time = Timespec.new;
    die 'clock_gettime failed' if clock_gettime($id, $time);
    $time.seconds * 1_000_000_000 + $time.nanoseconds
}
