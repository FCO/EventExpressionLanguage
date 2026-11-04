unit module LogTransforms;

grammar LogLine {
    token TOP { ^ $<time>=\d+ \s+ $<kind>=<-[\s]>+ \s+ $<id>=\d+ $ }
}
class LogActions {
    method TOP($/) { make %(timestamp=>+$<time>, type=>~$<kind>, id=>+$<id>) }
}
our sub grammar-line(Str $line, :$origin!, :$line-number!) is export {
    return Nil unless $line.trim;
    my $match = LogLine.parse($line, :actions(LogActions.new));
    die 'Expected: TIMESTAMP TYPE ID' unless $match;
    $match.made
}
our sub regex-line(Str $line, :$origin!, :$line-number!) is export {
    return Nil unless $line.trim;
    my $match = $line ~~ /^ (\d+) \s+ (\S+) \s+ (\d+) $/;
    die 'Expected: TIMESTAMP TYPE ID' unless $match;
    %(timestamp=>+$match[0], type=>~$match[1], id=>+$match[2])
}
our sub split-line(Str $line, :$origin!, :$line-number!) is export {
    return Nil unless $line.trim;
    my @fields = $line.words;
    die 'Expected: TIMESTAMP TYPE ID' unless @fields.elems == 3 && @fields[0] ~~ /^\d+$/ && @fields[2] ~~ /^\d+$/;
    %(timestamp=>+@fields[0], type=>@fields[1], id=>+@fields[2])
}
our class ParsedLog {
    has $.timestamp;
    has $.type;
    has $.id;
}
our sub object-line(Str $line, :$origin!, :$line-number!) is export {
    my $record = split-line($line, :$origin, :$line-number);
    $record.defined ?? ParsedLog.new(|$record) !! Nil
}
# One source line may generate several events, in timestamp order.
our sub burst-line(Str $line, :$origin!, :$line-number!) is export {
    my $record = split-line($line, :$origin, :$line-number);
    return Nil unless $record.defined;
    (%(|$record, type=>'start'), %(|$record, type=>'finish')).List
}
