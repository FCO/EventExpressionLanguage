use lib 'lib';
use EEL;
event Knocked {
    has $.ip;
    pattern TOP {
        <first=.event(:type<knock>, :port(1))>
        { $!ip = $<first>.ip }
        <.event(:type<knock>, :port(2), :ip($!ip))>
        <.event(:type<knock>, :port(3), :ip($!ip))>
        [ <.event(:type<knock>, :port(1), :ip($!ip))>
          <.event(:type<knock>, :port(2), :ip($!ip))>
          <.event(:type<knock>, :port(3), :ip($!ip))> ] ** 1
    }
}
(1,2,3,1,2,3,1,2,3).map(-> $port { %(type => 'knock', :$port, ip => '127.0.0.1') }).Supply.match(Knocked).tap: -> $knock { say "knocked: {$knock.ip}" };
