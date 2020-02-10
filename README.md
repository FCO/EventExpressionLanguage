# EventExpressionLanguage


It's an idea of a solution for complex event processing, it's divided into 3 main parts:

- parse:

  it should parse a language based on raku's grammar and raku's class
  
  | syntax | meaning |
  | - | - |
  | 5min | time applied for the last construct (unitis: s, min, h, days) |
  | [ A ] | group |
  | A & B | A AND B in any order |
  | A && B | A AND B on that order |
  | A \| B | A XOR B |
  | bla() | matches an event called `bla` |
  | bla( value > 3 ) | matches an event called `bla` where value is greater than 3 |
  | $ble | event propert called ble |
  | #bli | internal name for a specific event |
  | ?attr = #blo.attr | test if `attr` is equal to `#blo.attr` only if `#blo` is defined |
  | [ bla( #blabla, ?id == #bleble.id ) & ble( #bleble, ?id == #blabla.id ) ] 5min | matches 2 events (`bla` and `ble`) at any order that has the same id and were dispatcher at max 5 min interval

    it should check most of things on parse time. its first draft is [here](https://github.com/FCO/EventExpressionLanguage/blob/master/lib/EventGrammar.pm6)
    and some exaples [here](https://github.com/FCO/EventExpressionLanguage/tree/master/examples) and a code to run this [here](https://github.com/FCO/EventExpressionLanguage/blob/master/bin/parser.p6)

    it should be transformed into something like this:

  ```perl6
  my @rules =
      {
          cmd      => "query",
          query    => %( :type("==" => "temperature"), :value(">" => 40) ),
          id       => "#temp",
          store    => < value area >,
          next     => {
              cmd      => "query",
              query    => %( :type("==" => "humidity"), :value("<" => 20), :area("==" => -> %state { %state<#temp><area> }) ),
              id       => "#hum",
              store    => < value area >,
              next     => {
                  cmd      => "dispatch",
                  data     => -> %state --> Hash() { :type<fire-risk>, :area(%state<#temp><area>), :temperature(%state<#temp><value>), :humidity(%state<#hum><value>) },
              }
          }
      },
      {
          cmd      => "query",
          query    => %( :type("==" => "humidity"),    :value("<" => 20) ),
          id       => "#hum",
          store    => < value area >,
          next     => {
              cmd      => "query",
              query    => %( :type("==" => "temperature"), :value(">" => 40), :area("==" => -> %state { %state<#hum><area> }) ),
              id       => "#temp",
              store    => < value area >,
              next     => {
                  cmd      => "dispatch",
                  data     => -> %state --> Hash() { :type<fire-risk>, :area(%state<#temp><area>), :temperature(%state<#temp><value>), :humidity(%state<#hum><value>) },
              }
          }
      }
  ;
  ```
  
- runner:
  
  It should accept the structure created by the parser and use it to add some queries on the query storage.
  It should connect to N streams (log file, kinesis, kafka, eventsource, websocket, rabit MQ, etc) and following
  the given rules, generate new events.
  There is an example of it should work [here](https://github.com/FCO/EventExpressionLanguage/blob/master/bin/runner.p6)
  Once you describe what properties (and possibly those types) each event shoud have, it will also validate events, and
  create a error event always it finds an invalid event.
  
- query storage:
  
  is a way to store queries and when the events are dispatched, find what queries match that object and that way match each part of the track.
  currently it's being implemented [here](https://github.com/FCO/EventExpressionLanguage/blob/master/lib/QueryStorage.pm6),
  but optimaly it should be an central process (as a database).
