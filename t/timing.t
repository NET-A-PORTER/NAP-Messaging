#!perl
use NAP::policy 'test','tt';
use NAP::Messaging::Timing;
use Time::HiRes 'sleep';

package FakeLogger {
    use NAP::policy 'class','tt';

    has lines => (
        is => 'ro',
        isa => 'ArrayRef',
        default => sub { [] },
        traits => [ 'Array' ],
        handles => { add_line => 'push' },
    );

    sub info { my ($self) = shift; $self->add_line(['info',"@_"]) }
};

my $l = FakeLogger->new;
my $t = NAP::Messaging::Timing->new({
    logger => $l,
    details => [some => ['useful','info']],
});
sleep(0.1);
$t->stop(more=>'info');

cmp_deeply(
    $l->lines,
    [
        ['info','{"event":"start","some":["useful","info"]}' ],
        ['info',re(qr(\A\{"event":"stop","time_taken":0\.1\d+,"some":\["useful","info"\],"more":"info"\}\z)) ],
    ],
    'time logged ok')
    or note p $l->lines;

done_testing;
