use lib 'lib';
use EEL;
event Bla {
    pattern TOP {
        <test1=.event(:type<t1>)>
        { say $<test1>.data<something> }
        <test2=.event(:type<t2>)>
    }
}
({type => 't1', something => 'data'}, {type => 't2'}).Supply.match(Bla).tap: *.say;
