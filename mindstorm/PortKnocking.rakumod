########################
# Emits when finds the secret knocking
########################
use lib 'lib';
use EEL;
event knocked-the-secret {
  has $.ip;

  pattern TOP {
    <first=.event(:type<request>, :1port)> { $!ip = $<first><ip> }
    <.event(:type<request>, :2port, :$!ip)>
    <.event(:type<request>, :3port, :$!ip)>
    [
      <.event(:type<request>, :1port, :$!ip)>
      <.event(:type<request>, :2port, :$!ip)>
      <.event(:type<request>, :3port, :$!ip)>
    ] ** 2
  }
}

