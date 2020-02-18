#use Grammar::Tracer;
use X::Event::ParseError;
unit grammar EventGrammar;

method parse-error($match, $msg) {
    die X::Event::ParseError.new(:$match, :$msg, :file($*EEL-FILE))
}

token TOP {
#    :my %*events;
    <.ws> <declarator>* %% <.ws>
}

token name { <[\w-]>+ }
token mp-name { <local-var> <term>+ }

proto token term      { *                  }
token term:sym<key>   { '.' <name>         }
token term:sym<index> { "[" ~ "]" $<i>=\d+ }

proto rule declarator {*}
rule declarator:sym<event> {
    :my %*local-vars := SetHash.new;
    :my $*event-name;
    <sym> <name>
    {
        $*event-name = ~$<name>;
        self.parse-error: $<name>, "Event '{ $*event-name }' already defined"
            if %*events{ $*event-name }:exists
    }
    '{' ~ '}' [
        :my %*attrs;
        <decl-body>
    ]
    {
        %*events{ $*event-name } = %*attrs
    }
}

rule decl-body {
    <declare-attr>* %% ";"
    <match-block>?
}

proto rule declare-attr {*}
rule declare-attr:sym<setter> {
    "has" <event-attr>
    {
        self.parse-error: $<event-attr>, "Event '$*event-name' already defined an attr called '{$<event-attr>}'"
            if %*attrs{~$<event-attr>}:exists
    }
    "=" <setter=.lval>
    {
        %*attrs{~$<event-attr>} = Any
    }
}
rule declare-attr:sym<nosetter> {
    "has" <event-attr>* %% ","
        {
            for $<event-attr> {
                self.parse-error: $_, "Event '$*event-name' already defined an attr called '{.Str}'"
                        if %*attrs{.Str}:exists;
                %*attrs{.Str}++
            }
    }
}

rule match-block {
    "match" '{' ~ '}' <statement-time-mod>*
}

proto token time-unit    { *                       }
token time-unit:sym<s>   { <sym> [ "econd" "s"? ]? }
token time-unit:sym<min> { <sym> [ "ute"   "s"? ]? }
token time-unit:sym<h>   { <sym> [ "our"   "s"? ]? }
token time-unit:sym<d>   { <sym> [ "ay"    "s"? ]? }

token time-mod {
    $<val>=\d+<.ws>?<time-unit>
}

rule statement-time-mod {
    <statement> <time-mod>?
}

proto rule statement {*}
rule statement:sym<event-match> {
    <event-match> [ <st-infix-op> <statement> ]?
}
rule statement:sym<group> {
    :my %*local-vars := SetHash.new;
    '[' ~ ']' <statement>*
}
#rule statement:sym<infix> {
#    <event-match> <st-infix-op> <statement>
#}

rule event-match {
    :my $*id;
    <name> "(" ~ ")" <event-match-content>* %% ','
}

proto token st-infix-op   { *     }
token st-infix-op:sym<&>  { <sym> }
token st-infix-op:sym<&&> { <sym> }
token st-infix-op:sym<|>  { <sym> }

proto rule event-match-content {*}
token event-match-content:sym<id> {
    <local-var>
    {
        $*id = ~$<local-var>;
        if %*local-vars{$*id}:exists {
            self.parse-error: $<local-var>, "Id '{$*id}' already in use";
        }
        %*local-vars{$*id}++
    }
}
rule event-match-content:sym<condition> {
    <name> <op> <lval>
}
rule event-match-content:sym<opt-condition> {
    "?"<name> <op> <lval>
}
token local-var  { '#' <?> <name> }
token event-attr { '$' <?> <name> }

token vars { <local-var> | <event-attr> }

proto token val    { *                       }
rule  val:sym<num> { ["+"|"-"]? \d+["."\d+]? }
rule  val:sym<str> { (["'"|'"']) ~ $0 .*?    }
token val:sym<var> { <vars> ['.'<name>]*     }

proto rule lval          { *           }
rule lval:sym<operation> { <operation> }
rule lval:sym<val>       { <val>       }
rule lval:sym<lvar>      { <mp-name>   }

proto token prefix-op    { *   }
token prefix-op:sym<not> { "!" }
token prefix-op:sym<so>  { "?" }

proto token infix-op      { *   }
token infix-op:sym<plus>  { "+" }
token infix-op:sym<minus> { "-" }
token infix-op:sym<times> { "*" }
token infix-op:sym<div>   { "/" }

proto rule operation       { *                       }
rule operation:sym<prefix> { <prefix-op> <lval>      }
rule operation:sym<infix>  { <val> <infix-op> <lval> }

proto token op   { *    }
token op:sym<eq> { "==" }
token op:sym<gt> { ">"  }
token op:sym<ge> { ">=" }
token op:sym<lt> { "<"  }
token op:sym<le> { "<=" }