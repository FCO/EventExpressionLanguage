use lib 'lib';
use EEL;

# Each valid conclusion of + is emitted. Earlier results remain independent.
event Progress {
    has $.count;
    has $.bytes;
    pattern TOP {
        :!ignore-unexpected
        <start=.event(:type<upload>)>
        <chunks=.event(:type<chunk>, :id($<start>.data<id>))>+
        { $!count = $<chunks>.elems; $!bytes = $<chunks>.map(*.data<bytes>).sum }
    }
}
(
    {type => 'upload', id => 1},
    {type => 'chunk', id => 1, bytes => 100},
    {type => 'chunk', id => 1, bytes => 200},
    {type => 'chunk', id => 1, bytes => 50},
).Supply.match(Progress).tap: -> $progress { say "chunks={$progress.count} bytes={$progress.bytes}" };
# OUTPUT: chunks=1 bytes=100
# OUTPUT: chunks=2 bytes=300
# OUTPUT: chunks=3 bytes=350
