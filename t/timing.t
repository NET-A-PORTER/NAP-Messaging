#!perl
use NAP::policy 'test','tt';
use NAP::Messaging::Timing;
use Time::HiRes 'sleep';
use Log::Log4perl qw(:levels);

package FakeLogger {
    use NAP::policy 'class','tt';

    has lines => (
        is => 'ro',
        isa => 'ArrayRef',
        default => sub { [] },
        traits => [ 'Array' ],
        handles => { add_line => 'push' },
    );

    sub log { my ($self, $level) = (shift, shift); $self->add_line([$level, "@_"]) }
};

package FakeGraphite {
    use NAP::policy qw(class tt);

    has metrics => (
        is => 'ro',
        isa => 'ArrayRef[HashRef]',
        default => sub { [] },
        traits => [ 'Array' ],
        handles => { add_metrics => 'push' },
    );

    sub send {
        my ($self, %args) = @_;
        $self->add_metrics({
            timestamp => (keys %{$args{data}})[0],
            data => (values %{$args{data}})[0],
        });
    }
}

my $l = FakeLogger->new;
my $g = FakeGraphite->new;
my $t = NAP::Messaging::Timing->new({
    logger => $l,
    graphite => $g,
    graphite_path => [ test => \'type', \'missing' ],
    graphite_metrics => ['nosuch'],
    details => [some => ['useful','info'], type => 'testing'],
});
sleep(0.1);
$t->add_metrics(answer => 42);
$t->stop(more=>'info');

my $s = NAP::Messaging::Timing->new({
    logger => $l,
    start_log_level => 'WARN',
    stop_log_level => 'DEBUG',
    details => [such => ['logging']],
});
sleep(0.1);
$s->stop(wow=>'!');

cmp_deeply(
    $l->lines,
    [
        [$INFO,'{"event":"start","some":["useful","info"],"type":"testing"}' ],
        [$INFO,re(qr(\A\{"event":"stop","time_taken":0\.1\d+,"some":\["useful","info"\],"type":"testing","answer":42,"more":"info"\}\z)) ],
        [$WARN,'{"event":"start","such":["logging"]}' ],
        [$DEBUG,re(qr(\A\{"event":"stop","time_taken":0\.1\d+,"such":\["logging"\],"wow":"!"\}\z)) ],
    ],
    'time logged ok')
    or note p $l->lines;

cmp_deeply(
    $g->metrics,
    [
        {
            timestamp => re('\A\d+\z'),
            data => { test => { testing => {
                answer => 42, time_taken => re('0.1\d+'),
            } } }
        }
    ],
);

done_testing;
