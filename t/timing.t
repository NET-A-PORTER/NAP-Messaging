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

my $l = FakeLogger->new;
my $t = NAP::Messaging::Timing->new({
    logger => $l,
    details => [some => ['useful','info']],
});
sleep(0.1);
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
        [$INFO,'{"event":"start","some":["useful","info"]}' ],
        [$INFO,re(qr(\A\{"event":"stop","time_taken":0\.1\d+,"some":\["useful","info"\],"more":"info"\}\z)) ],
        [$WARN,'{"event":"start","such":["logging"]}' ],
        [$DEBUG,re(qr(\A\{"event":"stop","time_taken":0\.1\d+,"such":\["logging"\],"wow":"!"\}\z)) ],
    ],
    'time logged ok')
    or note p $l->lines;

done_testing;
