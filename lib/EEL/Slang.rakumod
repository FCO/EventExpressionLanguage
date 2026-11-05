use nqp;
use experimental :rakuast;
use EEL::Definition;
use EEL::Condition;
unit module EEL::Slang;

role Grammar[Mu $regular-statementlist, Mu $regular-arglist, Mu $regular-block, Mu $regular-paren, Mu $regular-square, Mu $regular-brace] is export {
    token package-declarator:sym<event> {
        'event' <.kok> <package-def('event')> <.set_braid_from(self)>
    }
    token routine-declarator:sym<pattern> {
        :my $*EEL-PATTERN = True;
        :my $*EEL-DEFINITION;
        :my @*EEL-LOCALS;
        :my $*EEL-POSITIONAL = 0;
        'pattern' <.end-keyword> <method-def=.key-origin('method-def', 'method')>
    }
    # Only the outer method body speaks EEL. Embedded blocks and ordinary
    # methods continue through the host parser and resolver.
    method statementlist(|) {
        if (try $*EEL-PATTERN) && (try $*BLOCK ~~ RakuAST::Method) { self.eel-body }
        else { $regular-statementlist.(self) }
    }
    token eel-body {
        :my $*EEL-PATTERN = False;
        <.ws> <eel-alt>? <.ws>
    }
    rule eel-alt { '||'? <eel-unordered-alt>+ % '||' }
    rule eel-unordered-alt { [ '|' <!before '|'> ]? <eel-and>+ % [ '|' <!before '|'> ] }
    rule eel-and { [ '&' <!before '&'> ]? <eel-ordered>+ % [ '&' <!before '&'> ] }
    rule eel-ordered { [ '&&' <!before '&'> ]? <eel-shuffle>+ % [ '&&' <!before '&'> ] }
    rule eel-shuffle { '&&&'? <eel-sequence>+ % '&&&' }
    rule eel-sequence { <eel-piece>+ }
    rule eel-goal {
        '~' <!before '~'> <closer=eel-piece> <body=eel-piece>
    }
    rule eel-piece { <eel-atom> <eel-quantifier>? }
    token eel-quantifier {
        '**' <.ws> $<min>=\d+ [ <.ws> '..' <.ws> $<max>=[\d+|'*'] ]?
        | $<short>=[<[?*+]>] $<selection>=[ '?' | '!' ]?
    }
    token eel-window { $<amount>=[\d+ ['.' \d+]?] $<unit>=['milliseconds'|'millisecond'|'seconds'|'second'|'minutes'|'minute'|'months'|'month'|'years'|'year'|'hours'|'hour'|'days'|'day'|'min'|'sec'|'ms'|'s'|'h'|'d'|'m'|'y'] <!before \w> }
    token eel-atom {
        | <eel-goal>
        | <eel-group>
        | <eel-call>
        | <eel-adverb>
        | <eel-local>
        | <?before '{'> <block>
    }
    token eel-group {
        :my $*BLOCK;
        :my @*EEL-LOCALS;
        $<open>=[ '[' | '(' ]
        :my $*EEL-GROUP-INDEX;
        { $*EEL-GROUP-INDEX = cap($/, 'open').Str eq '(' ?? $*EEL-POSITIONAL++ !! Nil }
        <.enter-block-scope('Block')>
        <.ws> <eel-alt>? <.ws>
        [ <?{ cap($/, 'open').Str eq '[' }> ']' | <?{ cap($/, 'open').Str eq '(' }> ')' ]
        <.leave-block-scope>
    }
    method arglist(|args) {
        my $*IN_REGEX_ASSERTION = so nqp::getlexdyn('$*EEL-COLON-ARGS');
        my $*EEL-COLON-ARGS = False;
        $regular-arglist.(self, |args)
    }
    method circumfix:sym<( )>(|args) {
        my $*IN_REGEX_ASSERTION = False;
        my $*EEL-COLON-ARGS = False;
        $regular-paren.(self, |args)
    }
    method circumfix:sym<[ ]>(|args) {
        my $*IN_REGEX_ASSERTION = False;
        my $*EEL-COLON-ARGS = False;
        $regular-square.(self, |args)
    }
    method circumfix:sym<{ }>(|args) {
        my $*IN_REGEX_ASSERTION = False;
        my $*EEL-COLON-ARGS = False;
        $regular-brace.(self, |args)
    }
    method block(|args) {
        my $*IN_REGEX_ASSERTION = False;
        my $*EEL-COLON-ARGS = False;
        $regular-block.(self, |args)
    }
    token eel-call {
        :my $*EEL-COLON-ARGS = False;
        '<' [ $<assertion>=[ '?' | '!' ] | [ $<silent>='.' ]? ] $<name>=[<[\w-]>+]
        [ '=' [ '.' | $<assertion>=[ '?' | '!' ] ] $<target>=[<[\w-]>+] ]?
        <.ws> [ '(' <arglist> ')' | ':' { $*EEL-COLON-ARGS = True } <.ws> <arglist> ]? <.ws> '>'
    }
    token eel-local {
        ':' <?before 'my' <.ws>> <statement> ';'
    }
    token eel-adverb {
        ':' [ <eel-window> | $<partition>='partition' <.ws> <block>
            | [ $<negation>='!' ]? $<ignore>='ignore-unexpected' <!before <[\w-]>> ]
    }
}

sub cap(Mu $match, Str $key) {
    my $v := nqp::atkey($match.hash, $key);
    return Nil if nqp::isnull($v);
    nqp::islist($v) ?? (0 ..^ nqp::elems($v)).map({ nqp::atpos($v, $_) }).List !! $v
}
sub node(Str $kind, Mu $/, @children = [], :$name = '', :%properties = {}, :$code, :$read-state, :$write-state, :$arguments-code) {
    my $prefix = $/.orig.substr(0, $/.from);
    my $line = $prefix.comb("\n").elems + 1;
    my $column = $prefix.chars - ($prefix.rindex("\n") // -1);
    EEL::Definition.new(:$kind, :source($/.Str), :$line, :$column, :$name, :@children, :%properties, :$code, :$read-state, :$write-state, :$arguments-code)
}
sub combine(Str $kind, Mu $/, @children) {
    @children.elems == 1 ?? @children[0] !! node($kind, $/, @children)
}
# A modifier written before the first alternative/conjunction belongs to the
# surrounding scope. An explicit leading operator marks a branch-local prefix.
sub scope-prefix($body) {
    return $body unless $body.kind eq any(<alternative ordered-alternative unordered ordered shuffle>);
    return $body if $body.source.trim.starts-with('|') || $body.source.trim.starts-with('&');
    my @prefix;
    sub peel($node) {
        if $node.kind eq 'sequence' {
            my @rest = $node.children;
            while @rest && @rest[0].kind eq any(<partition ignore-unexpected local window-start>) {
                @prefix.push(@rest.shift);
            }
            return $node.clone(:children(@rest));
        }
        return $node unless $node.kind eq any(<alternative ordered-alternative unordered ordered shuffle>);
        my @children = $node.children;
        @children[0] = peel(@children[0]);
        @children.shift if @prefix && @children[0].kind eq 'sequence' && !@children[0].children;
        @children.elems == 1 ?? @children[0] !! $node.clone(:@children)
    }
    my $rest = peel($body);
    @prefix ?? $body.clone(:kind<sequence>, :children[|@prefix,$rest]) !! $body
}
sub val(Mu $value) { RakuAST::Literal.from-value($value) }
sub thunk($expression) {
    RakuAST::Block.new(:implicit-topic(False), :body(RakuAST::Blockoid.new(
        RakuAST::StatementList.new(RakuAST::Statement::Expression.new(:$expression)))))
}
sub condition-call(Str $method, *@args) {
    RakuAST::ApplyPostfix.new(:operand(val(EEL::Condition)), :postfix(RakuAST::Call::Method.new(
        :name(RakuAST::Name.from-identifier($method)), :args(RakuAST::ArgList.new(|@args)))))
}
sub unparen($expression) {
    my $e=$expression;
    while $e ~~ RakuAST::Circumfix::Parentheses {
        my @statements=$e.semilist.statements;
        return $e unless @statements.elems == 1 && @statements[0] ~~ RakuAST::Statement::Expression;
        $e=@statements[0].expression;
    }
    $e
}
# Resolve through the AST lookup API available in released Rakudo versions.
# Only rewrite CORE operations: lexical replacements must keep their semantics.
sub resolves-to-setting($lookup, Str $name) {
    return False unless $lookup.is-resolved;
    my $resolution=$lookup.resolution;
    return False unless $resolution ~~ RakuAST::CompileTimeValue;
    return True if $resolution ~~ RakuAST::Declaration::External::Setting
        && $resolution.lexical-name eq $name;
    my $resolver := nqp::getlexdyn('$*R');
    return False if nqp::isnull($resolver) || !nqp::isconcrete($resolver);
    my $setting := $resolver.resolve-lexical-constant-in-setting($name);
    so nqp::isconcrete($setting) && $setting ~~ RakuAST::CompileTimeValue
        && nqp::eqaddr($resolution.compile-time-value, $setting.compile-time-value)
}
sub junction-kind($e) {
    if $e ~~ RakuAST::Call::Name && $e.name.canonicalize eq any(<any all one none>)
        && resolves-to-setting($e, '&' ~ $e.name.canonicalize) { return $e.name.canonicalize }
    if $e ~~ RakuAST::ApplyListInfix && $e.infix.operator eq any('|','&','^')
        && resolves-to-setting($e.infix, '&infix:<' ~ $e.infix.operator ~ '>') {
        return { '|' => 'any', '&' => 'all', '^' => 'one' }{$e.infix.operator};
    }
    ''
}
sub junction-ast($e) { so junction-kind($e).chars }
sub junction-children($e) { $e ~~ RakuAST::Call::Name ?? $e.args.args !! $e.operands }
sub comparison-ast($expression) {
    my $e=unparen($expression);
    return Nil unless $e ~~ RakuAST::ApplyInfix && $e.infix.operator eq any('==','!=','<','<=','>','>=');
    return Nil unless resolves-to-setting($e.infix, '&infix:«' ~ $e.infix.operator ~ '»');
    my @terms; my @ops;
    sub flatten($node) {
        if $node ~~ RakuAST::ApplyInfix && $node.infix.operator eq any('==','!=','<','<=','>','>=') {
            return unless resolves-to-setting($node.infix, '&infix:«' ~ $node.infix.operator ~ '»');
            flatten($node.left); @ops.push($node.infix.operator); @terms.push(unparen($node.right));
        } else { @terms.push(unparen($node)) }
    }
    flatten($e);
    return Nil unless @terms.grep(* ~~ RakuAST::WhateverCode::Argument).elems == 1;
    my @parts;
    for @ops.kv -> $i,$operator {
        my $op=$operator;
        my ($left,$right)=@terms[$i,$i+1];
        my $bound;
        if $left ~~ RakuAST::WhateverCode::Argument { $bound=$right }
        elsif $right ~~ RakuAST::WhateverCode::Argument {
            $bound=$left; $op=({'<'=>'>','<='=>'>=','>'=>'<','>='=>'<=','=='=>'==','!='=>'!='}){$op};
        } else { return Nil }
        if junction-ast($bound) {
            my @children=junction-children($bound).map({ condition-call('comparison',val($op),$_) });
            @parts.push(condition-call('junction',val(junction-kind($bound)),|@children));
        } else { @parts.push(condition-call('comparison',val($op),$bound)) }
    }
    @parts.elems == 1 ?? @parts[0] !! condition-call('junction',val('all'),|@parts)
}
sub indexed-condition($expression) {
    my $e=unparen($expression);
    my $comparison=comparison-ast($e);
    return $comparison if $comparison.defined;
    if junction-ast($e) {
        return condition-call('junction',val(junction-kind($e)),|junction-children($e).map({
            indexed-condition($_) // condition-call('literal',$_)
        }));
    }
    Nil
}
sub indexed-arguments($args) {
    RakuAST::ArgList.new(|$args.args.map(-> $arg {
        if $arg ~~ RakuAST::ColonPair::Value {
            my $optimized=indexed-condition($arg.value);
            $optimized.defined ?? RakuAST::ColonPair::Value.new(:key($arg.key),:value($optimized)) !! $arg
        } else { $arg }
    }))
}

sub expr($node) {
    return RakuAST::ApplyPostfix.new(:operand($node.factory), :postfix(RakuAST::Call::Term.new)) if $node.factory;
    my @children = $node.children.map({ expr($_) });
    # Embedded host AST is emitted as a closure, never evaluated by the parser.
    my $code = $node.code // val(Nil);
    RakuAST::ApplyPostfix.new(:operand(val($node)), :postfix(RakuAST::Call::Method.new(
        :name(RakuAST::Name.from-identifier('materialize')),
        :args(RakuAST::ArgList.new($code, $node.read-state // val(Nil), $node.write-state // val(Nil), $node.arguments-code // val(Nil), |@children)))))
}

role Actions is export {
    method package-declarator:sym<event>(Mu $/) {
        self.DECLARATOR($/, cap($/, 'package-def').ast);
    }
    method routine-declarator:sym<pattern>(Mu $/) {
        my $method = nqp::atkey($/.hash, 'method-def').ast;
        my $routine = $method.meta-object;
        $/.panic('A proto pattern must have a {*} body')
            if $routine.is_dispatcher && $*EEL-DEFINITION.defined;
        $routine does EEL::Definition::CompiledPattern;
        $routine.definition = $*EEL-DEFINITION // EEL::Definition.new(:kind<proto>, :name($routine.name));
        my $symbol = $routine.name.index(':sym<');
        if $symbol.defined {
            $routine.definition.properties<family> = $routine.name.substr(0,$symbol);
        }
        self.DECLARATOR($/, $method);
    }
    method eel-body(Mu $/) {
        my $body = cap($/, 'eel-alt') ?? scope-prefix(cap($/, 'eel-alt').made) !! node('sequence', $/);
        my @args;
        my $forkable = True;
        for ($*BLOCK.signature ?? $*BLOCK.signature.parameters !! []) -> $parameter {
            next if $parameter.invocant;
            my $name = $parameter.target.lexical-name;
            unless $name.chars { $forkable = False; next }
            my $value = RakuAST::Var::Lexical.new($name);
            if !($parameter.slurpy =:= RakuAST::Parameter::Slurpy) {
                $value = RakuAST::ApplyPrefix.new(:prefix(RakuAST::Prefix.new('|')), :operand($value));
            } elsif $parameter.named {
                $value = RakuAST::ColonPair::Value.new(:key($parameter.names[0]), :$value);
            }
            @args.push($value);
        }
        my $arguments-code = thunk(RakuAST::Term::Capture.new(RakuAST::ArgList.new(|@args)));
        $*EEL-DEFINITION = node('pattern', $/, [$body], :name($*BLOCK.name.canonicalize),
            :properties({forkable-signature => $forkable}), :$arguments-code);
        self.attach($/, RakuAST::StatementList.new(
            RakuAST::Statement::Expression.new(:expression(RakuAST::ApplyInfix.new(
                :left(RakuAST::Var::Lexical.new('$/')), :infix(RakuAST::Infix.new('=')), :right(RakuAST::Term::Self.new)))),
            |@*EEL-LOCALS,
            RakuAST::Statement::Expression.new(:expression(expr($*EEL-DEFINITION)))));
    }
    method eel-alt(Mu $/) { make combine('ordered-alternative', $/, cap($/, 'eel-unordered-alt')>>.made) }
    method eel-unordered-alt(Mu $/) { make combine('alternative', $/, cap($/, 'eel-and')>>.made) }
    method eel-and(Mu $/) { make combine('unordered', $/, cap($/, 'eel-ordered')>>.made) }
    method eel-ordered(Mu $/) { make combine('ordered', $/, cap($/, 'eel-shuffle')>>.made) }
    method eel-shuffle(Mu $/) { make combine('shuffle', $/, cap($/, 'eel-sequence')>>.made) }
    method eel-sequence(Mu $/) { make node('sequence', $/, cap($/, 'eel-piece')>>.made) }
    method eel-goal(Mu $/) {
        make node('goal', $/, [cap($/, 'closer').made, cap($/, 'body').made]);
    }
    method eel-piece(Mu $/) {
        my $n = cap($/, 'eel-atom').made;
        $n = node('repeat', $/, [$n], :properties(cap($/, 'eel-quantifier').made)) if cap($/, 'eel-quantifier');
        make $n;
    }
    method eel-quantifier(Mu $/) {
        my ($min, $max);
        if cap($/, 'short') {
            ($min, $max) = do given cap($/, 'short').Str { when '?' { 0, 1 }; when '*' { 0, Inf }; default { 1, Inf } }
        } else {
            $min = cap($/, 'min').Str.Int;
            $max = cap($/, 'max') ?? (cap($/, 'max').Str eq '*' ?? Inf !! cap($/, 'max').Str.Int) !! $min;
        }
        $/.panic('Pattern repetition has an inverted range') if $min > $max;
        my $suffix = cap($/, 'selection').Str;
        my $selection = $suffix eq '?' ?? 'first' !! ($suffix eq '!' ?? 'last' !! 'all');
        make %(:$min, :$max, :$selection);
    }
    method eel-window(Mu $/) {
        my %units;
        for (1/1000)=><ms millisecond milliseconds>, 1=><s sec second seconds>, 60=><min minute minutes>,
            3600=><h hour hours>, 86400=><d day days>, 2592000=><m month months>, 31536000=><y year years> -> $pair {
            %units{$_} = $pair.key.Numeric for $pair.value.list;
        }
        my $seconds = cap($/, 'amount').Str.FatRat * %units{cap($/, 'unit').Str};
        my $ns = $seconds * 1_000_000_000;
        $/.panic('Window duration must be an integer number of nanoseconds') unless $ns == $ns.Int;
        make %(:seconds($seconds == $seconds.Int ?? $seconds.Int !! $seconds), :nanoseconds($ns.Int), :clock<event>, :inclusive);
    }
    method eel-atom(Mu $/) {
        make cap($/, 'eel-goal') ?? cap($/, 'eel-goal').made
            !! cap($/, 'eel-call') ?? cap($/, 'eel-call').made
            !! cap($/, 'eel-adverb') ?? cap($/, 'eel-adverb').made
            !! cap($/, 'eel-local') ?? cap($/, 'eel-local').made
            !! cap($/, 'block') ?? node('code', $/, :code(cap($/, 'block').ast))
            !! cap($/, 'eel-group').made;
    }
    method eel-group(Mu $/) {
        my @children = cap($/, 'eel-alt') ?? [scope-prefix(cap($/, 'eel-alt').made)] !! [];
        my $capturing = cap($/, 'open').Str eq '(';
        my %properties = $capturing ?? (index => $*EEL-GROUP-INDEX) !! ();
        my $n = node($capturing ?? 'capture-group' !! 'group', $/, @children, :%properties);
        $*BLOCK.replace-body(RakuAST::Blockoid.new(RakuAST::StatementList.new(|@*EEL-LOCALS,
            RakuAST::Statement::Expression.new(:expression(expr($n))))));
        self.attach($/, $*BLOCK);
        make $n.clone(:factory($*BLOCK));
    }
    method eel-call(Mu $/) {
        $/.panic('A silent call cannot also have a capture alias') if cap($/, 'silent') && cap($/, 'target');
        my $context-free = !cap($/, 'arglist') || so cap($/, 'arglist').ast.args.map({
            $_ ~~ RakuAST::ColonPair && .has-compile-time-value
        }).all;
        $/.panic('An assertion prefix cannot also have a capture alias')
            if cap($/, 'target') && ($/.Str.starts-with('<?') || $/.Str.starts-with('<!'));
        my $is-assertion=cap($/, 'assertion').Str;
        my $capture=$is-assertion.chars
            ?? (cap($/, 'target') ?? cap($/, 'name').Str !! '')
            !! (cap($/, 'silent') ?? '' !! cap($/, 'name').Str);
        my $n=node('call', $/, :name((cap($/, 'target') // cap($/, 'name')).Str),
            :properties({capture => ($is-assertion.chars ?? '__eel-asserted' !! $capture), :$context-free}),
            :code(cap($/, 'arglist') ?? thunk(RakuAST::Term::Capture.new(((cap($/, 'target') // cap($/, 'name')).Str eq 'event') ?? indexed-arguments(cap($/, 'arglist').ast) !! cap($/, 'arglist').ast)) !! Nil));
        make $is-assertion.chars
            ?? node('assertion',$/,[$n],:name($n.name),:properties({positive=>$is-assertion eq '?',:$capture}))
            !! $n;
    }
    method eel-local(Mu $/) {
        # Allocate the lexical in its enclosing scope, but defer its initializer
        # until the recognition reaches this instruction. Moving the declaration
        # itself into a thunk breaks lexical ownership and optimizer lowering.
        my $statement = cap($/, 'statement').ast;
        my $decl = $statement.expression;
        $/.panic(':my requires a simple lexical variable declaration') unless $decl ~~ RakuAST::VarDeclaration::Simple;
        my $initializer = $decl.initializer;
        $/.panic(':my currently supports assignment (=) initializers') if $initializer && $initializer !~~ RakuAST::Initializer::Assign;
        my $code = val(Nil);
        if $initializer {
            my $lookup = RakuAST::Var::Lexical.new($decl.lexical-name);
            $lookup.set-resolution($decl);
            $code = thunk(RakuAST::ApplyInfix.new(:left($lookup), :infix(RakuAST::Infix.new('=')), :right($initializer.expression)));
        }
        $decl.set-initializer(RakuAST::Initializer);
        @*EEL-LOCALS.push($statement);
        my $read = RakuAST::Var::Lexical.new($decl.lexical-name);
        $read.set-resolution($decl);
        my $write = RakuAST::Var::Lexical.new($decl.lexical-name);
        $write.set-resolution($decl);
        my $read-state = thunk($read);
        my $restore-op = $decl.lexical-name.substr(0, 1) eq any('@', '%') ?? ':=' !! '=';
        my $write-state = RakuAST::Block.new(:implicit-topic(True), :required-topic(True),
            :body(RakuAST::Blockoid.new(RakuAST::StatementList.new(
                RakuAST::Statement::Expression.new(:expression(RakuAST::ApplyInfix.new(
                    :left($write), :infix(RakuAST::Infix.new($restore-op)),
                    :right(RakuAST::Var::Lexical.new('$_')))))))));
        make node('local', $/, :name($decl.lexical-name), :$code, :$read-state, :$write-state);
    }
    method eel-adverb(Mu $/) {
        make cap($/, 'eel-window') ?? node('window-start', $/, :properties(cap($/, 'eel-window').made))
            !! cap($/, 'partition') ?? node('partition', $/, :properties({share-extractor => so cap($/, 'block').Str ~~ /^ \s* '{' \s* [ '.' '<' <[\w-]>+ '>' \s* ]+ % [ ',' \s* ] '}' \s* $/}), :code(cap($/, 'block').ast))
            !! node('ignore-unexpected', $/, :properties({enabled => !cap($/, 'negation')}));
    }
}
