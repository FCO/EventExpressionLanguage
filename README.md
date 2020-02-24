# EventExpressionLanguage

## Small example:

```
$ raku -MJSON::Fast -e '
loop {
  say to-json :!pretty, %(:type<bla>, :a(^100 .pick), :b(^100 .pick))
}
' | bin/eel -l=events2.log -e='
  event ble {
    has $a1 = #1.a;
    has $a2 = #2.a;
    has $b1 = #1.b;
    has $b2 = #2.b;
    match {[
      & bla(#1, a == 42, ?b == #2.b)
      & bla(#2, a == 13, ?b == #1.b)
    ]}
  }
'
{"a1":42,"a2":13,"b1":22,"b2":22,"timestamp":"2020-02-20T04:19:47.178670Z","type":"ble"}
{"timestamp":"2020-02-20T04:19:47.515712Z","type":"ble","b2":43,"b1":43,"a2":13,"a1":42}
{"b2":45,"type":"ble","timestamp":"2020-02-20T04:19:51.563406Z","a1":42,"a2":13,"b1":45}
{"b2":99,"type":"ble","timestamp":"2020-02-20T04:19:52.089484Z","a1":42,"a2":13,"b1":99}
{"b2":19,"type":"ble","timestamp":"2020-02-20T04:19:54.037338Z","a2":13,"a1":42,"b1":19}
{"b2":10,"type":"ble","timestamp":"2020-02-20T04:19:55.338196Z","a2":13,"a1":42,"b1":10}
{"b2":81,"timestamp":"2020-02-20T04:19:55.971652Z","type":"ble","a2":13,"a1":42,"b1":81}
{"b2":49,"timestamp":"2020-02-20T04:20:04.710167Z","type":"ble","a1":42,"a2":13,"b1":49}
{"a1":42,"a2":13,"b1":52,"b2":52,"timestamp":"2020-02-20T04:20:05.310459Z","type":"ble"}
{"b2":49,"timestamp":"2020-02-20T04:20:06.304376Z","type":"ble","a1":42,"a2":13,"b1":49}
^C
```

## What's it?

It's an idea of a solution for complex event processing, it's divided into 3 main parts:

- parse:

  it should parse a language based on raku's grammar and raku's class
  
  | syntax                                                                         | meaning                                                                                                        |
  | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
  | 5min                                                                           | time applied for the last construct (units: s, min, h, days)                                                   |
  | [ A ]                                                                          | group                                                                                                          |
  | A & B                                                                          | A AND B in any order                                                                                           |
  | A && B                                                                         | A AND B on that order                                                                                          |
  | A \| B                                                                         | A OR B                                                                                                         |
  | ** N                                                                           | indicates that the last matcher should be matched N times                                                      |
  | ** N..M                                                                        | indicates that the last matcher should be matched at least N times and max M                                   |
  | bla()                                                                          | matches an event called `bla`                                                                                  |
  | bla( value > 3 )                                                               | matches an event called `bla` where value is greater than 3                                                    |
  | $ble                                                                           | event propert called ble                                                                                       |
  | #bli                                                                           | internal name for a specific event                                                                             |
  | ?attr = #blo.attr                                                              | test if `attr` is equal to `#blo.attr` only if `#blo` is defined                                               |
  | [ bla( #blabla, ?id == #bleble.id ) & ble( #bleble, ?id == #blabla.id ) ] 5min | matches 2 events (`bla` and `ble`) at any order that has the same id and were dispatcher at max 5 min interval |

    it should check most of things on parse time. its first draft is [here](https://github.com/FCO/EventExpressionLanguage/blob/master/lib/EventGrammar.pm6)
    and some examples [here](https://github.com/FCO/EventExpressionLanguage/tree/master/examples) and a code to run this [here](https://github.com/FCO/EventExpressionLanguage/blob/master/bin/parser.p6)

    Something like this:
  ```
  event temperature { has $value, $area }
  event humidity    { has $value, $area }
  event fire-risk {
      has $temperature = #temp.value;
      has $humidity    = #hum.value;
      match {
          [
              & temperature(#temp, value > 40, ?area == #hum.area )
              & humidity(#hum, value < 20, ?area == #temp.area)
          ] 5min
      }
  }
  ```
    should be transformed into something like this:

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
  There are some examples of that should work [here](https://github.com/FCO/EventExpressionLanguage/blob/master/bin/runner.p6).
  
  Once you describe what properties (and possibly those types) each event should have, it will also validate events, and
  create a error event always it finds an invalid event.
  
  Each step of the recognition of the pattern should store on the QueryStorage along with the query itself the next steps
  for that pattern. So, for instance, your pattern is: `get-login-page(#login-page) post-login(form-id == #login-page.form-id, status-code == 200)`, then, it will add on the query storage the query: `{ :type<get-login-page> }`, and on it's data information saying that on the next it should match `{ :type<post-login>, :form-id(XXX), :status-code(200) }` when `XXX` is the `form-id` gotten from `get-login-page`.
  
- query storage:
  
  is a way to store queries and when the events are dispatched, find what queries match that object and that way match each part of the track.
  currently it's being implemented [here](https://github.com/FCO/EventExpressionLanguage/blob/master/lib/QueryStorage.pm6),
  but optimally it should be an central process (as a database).
