use nqp;
use experimental :rakuast;
use MONKEY-SEE-NO-EVAL;
use JSON::Fast;
use EEL;
use EEL::Metadata;
use EEL::Input;
use EEL::Clock;
use Event;
unit module EEL::CLI;

class Reader is export {
    has IO::Path $.path is required;
    has $!handle;
    has Str $!identity;
    has Buf $!buffer = Buf.new;
    has Int $!line = 0;
    method !open {
        my $handle = try $!path.open(:r, :bin);
        return False if !$handle.defined && !$!path.e;
        $handle.throw if $handle ~~ Failure;
        die "Cannot open $!path" unless $handle.defined;
        $!handle = $handle;
        $!identity = "{$!path.dev}:{$!path.inode}";
        $!line = 0;
        True
    }
    method eof { !$!handle.defined || $!handle.eof }
    method close { $!handle.close if $!handle.defined; $!handle = Nil }
    method !lines(Bool $final = False) {
        my @lines;
        loop {
            my $end = $!buffer.list.first(* == 10, :k);
            last unless $end.defined;
            my $bytes = $!buffer.subbuf(0, $end);
            $!buffer = Buf.new($!buffer.subbuf($end + 1).list);
            @lines.push([++$!line, $bytes]);
        }
        if $final && $!buffer.elems { @lines.push([++$!line, $!buffer]); $!buffer = Buf.new }
        @lines
    }
    method poll(Bool :$final = False --> List) {
        unless $!handle.defined {
            unless self!open {
                die "Cannot open $!path" if $final;
                return ().List;
            }
        }
        my @out;
        my $chunk = $!handle.read(65536);
        $!buffer.append($chunk) if $chunk.elems;
        @out.append(self!lines($final && self.eof));
        if !$final && $!path.e {
            my $identity = "{$!path.dev}:{$!path.inode}";
            if $identity ne $!identity && self.eof {
                @out.append(self!lines(True));
                self.close;
                @out.append(self.poll) if self!open;
            } elsif $!path.s < $!handle.tell {
                note "{$!path}: discarded incomplete line after truncation" if $!buffer.elems;
                $!buffer = Buf.new; $!handle.seek(0); $!line = 0;
                @out.append(self.poll);
            }
        }
        @out.List
    }
}

sub encode-event($value, %active = {}, Str $where = '$') is export {
    return Nil unless $value.defined;
    return $value if $value ~~ Str|Bool|Int|Rat;
    if $value ~~ Num {
        die "Non-finite number at $where" unless -Inf < $value < Inf;
        return $value;
    }
    return $value.Str if $value ~~ Date|DateTime|Instant;
    die "Cannot serialize callable at $where" if $value ~~ Callable;
    my $id = nqp::objectid(nqp::decont($value)).Str;
    die "Serialization cycle at $where" if %active{$id};
    my %next = |%active, $id => True;
    if $value ~~ Associative {
        return $value.map({ .key => encode-event(.value, %next, ($where ~ '.' ~ .key)) }).Hash;
    }
    if $value ~~ Positional {
        return $value.list.map({ encode-event($_, %next, "$where\[\]") }).Array;
    }
    my %out = type => $value.^name;
    if $value ~~ Event { %out<timestamp> = $value.timestamp.DateTime.Str; %out<event-id> = $value.event-id }
    for $value.^attributes -> $attribute {
        next unless $attribute.has_accessor;
        next if $attribute.package === Event || $attribute.package === Capture;
        my $name = $attribute.name.substr(2);
        next if %out{$name}:exists;
        %out{$name} = encode-event($value."$name"(), %next, ($where ~ '.' ~ $name));
    }
    die "Cannot serialize {$value.^name} at $where" if %out.elems == 1 && $value !~~ Event;
    %out
}

sub run-cli(@arguments, :$stdout! --> Int) is export {
    my (@modules, @events, @files, @inline);
    my $follow = False;
    my $transform-name;
    my $timestamp-field = "timestamp";
    my Real $merge-wait = 1;
    my $wait-specified = False;
    my $*OUT = $*ERR;
    my $phase = 2;
    CATCH { default { note .message; return $phase } }
    my @args = @arguments;
    while @args {
        my $arg = @args.shift;
        if $arg eq '--help' {
            $stdout.say: q:to/HELP/;
Usage: eel.raku [-e CODE] [--module Module] [--event Type] [options] [file ... | -]
  -e, --eval CODE          Define events inline; repeat to append code
  --module Module          Load a module; repeat to load more
  --event Type             Select an event; repeat to select more
                           Event alone loads its namesake module;
                           module alone selects its exported events
  --transform Module::fn   Convert each text line to events
  --timestamp-field Name  Timestamp input field (default: timestamp)
  --follow                 Follow one or more existing regular files
  --merge-wait Seconds     Wait for silent follow sources (default: 1)
  --help                   Show this help
Without files, read JSONL (or transformed text) from stdin.
HELP
            return 0;
        }
        if $arg eq '-e' || $arg eq '--eval' || $arg.starts-with('--eval=') {
            my $code=$arg.starts-with('--eval=') ?? $arg.substr(7) !! (@args.shift // die 'Missing --eval code');
            die 'Empty --eval code' unless $code.trim.chars;
            @inline.push($code); next;
        }
        if $arg eq '--timestamp-field' { $timestamp-field = @args.shift // die 'Missing timestamp field'; next }
        if $arg eq '--merge-wait' { $wait-specified = True; $merge-wait = +(@args.shift // die 'Missing merge wait'); die 'Invalid merge wait' unless 0 <= $merge-wait < Inf; next }
        if $arg eq '--transform' { $transform-name = @args.shift // die 'Missing --transform value'; next }
        if $arg.starts-with('--transform=') { $transform-name = $arg.substr(12); next }
        if $arg eq '--follow' { $follow = True; next }
        if $arg eq '--' { @files.append(@args); last }
        if $arg ~~ /^ '--' (module|event) [ '=' (.*) ]? $/ {
            my $name = ~$0;
            my $value = $1.defined ?? ~$1 !! (@args.shift // die "Missing --$name value");
            die "Empty --$name value" unless $value.chars;
            ($name eq 'module' ?? @modules !! @events).push($value);
            next;
        }
        die "Unknown option $arg" if $arg.starts-with('-') && $arg ne '-';
        @files.push($arg);
    }
    die 'Specify at least one --eval, --module or --event' unless @inline || @modules || @events;
    die '--merge-wait requires --follow' if $wait-specified && !$follow;
    die 'Empty timestamp field' unless $timestamp-field.chars;
    @modules = @events.unique unless @modules || @inline;
    die '--follow requires one or more regular files' if $follow && (!@files || @files.first(* eq '-').defined);
    my (%types, %loaded, %exported);
    if @inline {
        my $code="use EEL;\n";
        my @starts;
        for @inline -> $part {
            @starts.push($code.comb("\n").elems+1);
            $code ~= $part ~ "\n;\n";
        }
        my $ast;
        {
            CATCH { default {
                my $error=$_;
                my $where='--eval';
                if $error.^can('line') && $error.line.defined {
                    my $index=(^@starts.elems).grep({ @starts[$_] <= $error.line }).tail;
                    if $index.defined {
                        $where='--eval-'~($index+1)~':'~($error.line - @starts[$index] + 1);
                    }
                }
                die $where ~ ": " ~ $error.gist;
            } }
            $ast=$code.AST;
            # Give inline events their public names before running initializers.
            for $ast.find-nodes(RakuAST::Class) -> $declaration {
                my $type=$declaration.meta-object;
                next unless $type ~~ Mu:U && (try $type.^isa(Event)) && $type !=== Event;
                my $prefix='EEL::CLI::';
                $type.HOW.set_name($type,$type.^name.substr($prefix.chars)) if $type.^name.starts-with($prefix);
            }
            $ast.EVAL;
        }
        my $count=0;
        for $ast.find-nodes(RakuAST::Class) -> $declaration {
            my $type=$declaration.meta-object;
            next unless $type ~~ Mu:U && (try $type.^isa(Event)) && $type !=== Event;
            my $name=$declaration.name.defined ?? $declaration.name.canonicalize !! $type.^name;
            %types{$name}{$type.^name}=$type;
            %types{$type.^name}{$type.^name}=$type;
            %exported{$type.^name}=$type;
            $count++;
        }
        die 'No events declared in --eval code' unless $count;
    }
    for @modules -> $module {
        die "Invalid module name $module" unless $module ~~ /^ <[\w-]>+ [ '::' <[\w-]>+ ]* $/;
        require ::($module);
        my $package = ::($module);
        %loaded{$module} = $package;
        my @packages = $package;
        if $package ~~ Mu:U && (try $package.^isa(Event)) {
            %types{$module}{$package.^name} = $package;
        }
        my $exports = $package.WHO<EXPORT>;
        for $exports.WHO.values -> $namespace {
            next unless $namespace ~~ Mu:U;
            @packages.push($namespace);
            for $namespace.WHO.values -> $type {
                next unless $type ~~ Mu:U && (try $type.^isa(Event));
                %exported{$type.^name} = $type;
            }
        }
        for @packages -> $namespace {
            for $namespace.WHO.kv -> $name, $type {
                next unless $type ~~ Mu:U && (try $type.^isa(Event));
                %types{$name}{$type.^name} = $type;
                %types{$type.^name}{$type.^name} = $type;
            }
        }
    }
    die 'No exported events found in the specified modules' unless @events || %exported;
    my @patterns = @events ?? @events.map(-> $name {
        if !(%types{$name}:exists) && @modules.first({ $name.starts-with($_ ~ '::') }).defined {
            my $module = @modules.grep({ $name.starts-with($_ ~ '::') }).sort(*.chars).tail;
            my $type = %loaded{$module};
            for $name.substr($module.chars + 2).split('::') -> $part { $type = $type.WHO{$part} }
            %types{$name}{$type.^name} = $type if $type ~~ Mu:U && (try $type.^isa(Event));
        }
        my @found = (%types{$name} // {}).values;
        die "Unknown event $name" unless @found;
        die "Ambiguous event $name; use a qualified name" if @found.elems > 1;
        @found[0]
    }) !! %exported.sort(*.key).map(*.value);
    for @files.grep(* ne '-') { die "Unreadable file: $_" unless .IO.f && .IO.r }
    my $transform;
    if $transform-name.defined {
        my @parts = $transform-name.split('::');
        die 'Use --transform Module::function' unless @parts.elems >= 2;
        my $function = @parts.pop;
        my $module = @parts.join('::');
        die 'Invalid transform name' unless @parts.all ~~ /^ <[\w-]>+ $/ && $function ~~ /^ <[\w-]>+ $/;
        require ::($module);
        my $package = ::($module);
        $transform = $package.WHO{'&' ~ $function} // $package.WHO<EXPORT>.WHO<DEFAULT>.WHO{'&' ~ $function};
        die "Unknown transform $transform-name" unless $transform ~~ Callable:D;
    }
    my $source = Supplier.new;
    my $output = $source.Supply.match(|@patterns);
    $phase = 1;
    my $error;
    my $tap = $output.tap(-> $event {
        $stdout.say(to-json(encode-event($event), :!pretty)); $stdout.flush;
    }, quit => -> $exception { $error = $exception });
    LEAVE $tap.close if $tap.defined;
    @files = '-' unless @files;
    die 'stdin may only appear once' if @files.grep(* eq '-').elems > 1;
    my @channels = @files.map({ Channel.new });
    my $cancel = Promise.new;
    my @tasks;
    LEAVE {
        $cancel.keep(True) if $cancel.defined && $cancel.status == Planned;
        try $*IN.close if @files.first(* eq '-').defined && @tasks.first(*.status == Planned).defined;
        try .close for @channels;
        await @tasks if @tasks;
    }
    @tasks = @files.kv.map(-> $index, $file {
        start {
            CATCH { default { try @channels[$index].fail($_) } }
            my $reader = $file eq '-' ?? Nil !! Reader.new(:path($file.IO));
            LEAVE $reader.close if $reader.defined;
            my $origin = $file eq '-' ?? '<stdin>' !! $file;
            my $previous;
            sub publish($number, $bytes) {
                my @prepared;
                try {
                    my $text = $bytes.decode('utf8');
                    return if !$transform.defined && !$text.trim.chars;
                    my $result = $transform.defined
                        ?? $transform($text, :$origin, :line-number($number))
                        !! from-json($text);
                    return if $result === Nil;
                    die 'Transform must return a finite list' if $result ~~ List|Array && $result.is-lazy;
                    my @records = $result ~~ List|Array ?? $result.list !! ($result,);
                    for @records -> $record {
                        die 'Expected a JSON object' if !$transform.defined && $record !~~ Associative;
                        die 'Transform must return an event or a finite list of events'
                            unless $record.defined && ($record ~~ Associative || $record !~~ Str|Numeric|Bool|Callable|Positional);
                        my $view = snapshot($record,:$timestamp-field);
                        @prepared.push(PreparedInput.new(:event($record), :$view));
                    }
                    CATCH { default { note "$origin:$number: {.message}"; return } }
                }
                my $previous-after = $previous;
                for @prepared -> $record {
                    my $time = $record.view.fields<timestamp>;
                    if $previous-after.defined && $time < $previous-after {
                        die "$origin:$number: timestamp regression" unless $follow;
                        note "$origin:$number: ignored timestamp regression"; return;
                    }
                    $previous-after = $time;
                }
                $previous = $previous-after;
                for @prepared -> $record {
                    return if $cancel.status == Kept;
                    my $ack = Promise.new;
                    @channels[$index].send([$record, $number, $ack, monotonic()]);
                    await Promise.anyof($ack, $cancel);
                }
            }
            if $file eq '-' {
                my $number = 0;
                my $buffer = Buf.new;
                loop {
                    last if $cancel.status == Kept;
                    my $chunk = $*IN.read(65536);
                    last unless $chunk.elems;
                    $buffer.append($chunk);
                    loop {
                        my $end = $buffer.list.first(* == 10, :k);
                        last unless $end.defined;
                        publish(++$number, $buffer.subbuf(0,$end));
                        $buffer = Buf.new($buffer.subbuf($end+1).list);
                        last if $cancel.status == Kept;
                    }
                }
                publish(++$number,$buffer) if $buffer.elems;
            } else {
                loop {
                    last if $cancel.status == Kept;
                    for $reader.poll(:final(!$follow)) -> ($number, $bytes) { publish($number, $bytes); last if $cancel.status == Kept }
                    last if !$follow && $reader.eof;
                    sleep 0.1 if $follow && $reader.eof;
                }
            }
            @channels[$index].close;
        }
    });
    my @heads = @channels.map(-> $channel { start { $channel.receive } });

    my @ended = @channels.map({ False });
    my $last;
    my $status = 0;
    my @signals;
    if $follow {
        @signals.push(signal(SIGINT).tap({ $status = 130 }));
        @signals.push(signal(SIGTERM).tap({ $status = 143 }));
    }
    LEAVE { .close for @signals }
    loop {
        last if $status;
        my @ready;
        for @heads.kv -> $i, $head {
            next if @ended[$i];
            if $head.status == Broken {
                my $exception = $head.cause;
                if $exception ~~ X::Channel::ReceiveOnClosed { @ended[$i] = True; next }
                $exception.throw;
            }
            @ready.push($i) if $head.status == Kept;
        }
        last if @ended.all;
        if @ready {
            my $i = @ready.sort({ @heads[$^a].result[0].view.fields<timestamp> <=> @heads[$^b].result[0].view.fields<timestamp> || $^a <=> $^b }).head;
            my $can-emit = @ready.elems == @ended.grep(!*).elems;
            $can-emit ||= $follow && (monotonic() - @heads[$i].result[3]) / 1_000_000_000 >= $merge-wait;
            if $can-emit {
                my ($record, $number, $ack) = @heads[$i].result;
                if $last.defined && $record.view.fields<timestamp> < $last {
                    note "{@files[$i]}:$number: ignored late event";
                } else {
                    $last = $record.view.fields<timestamp>;
                    $source.emit($record);
                    $error.throw if $error.defined;
                }
                $ack.keep(True);
                @heads[$i] = start { @channels[$i].receive };

                next;
            }
        }
        sleep 0.01;
    }
    unless $follow { $source.done; $error.throw if $error.defined }
    $status
}
