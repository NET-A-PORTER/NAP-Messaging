#!perl
use NAP::policy 'test','tt';
use Test::Fatal;
use Test::NAP::Messaging;

package MyProducer {
    use NAP::policy 'class';
    with 'NAP::Messaging::Role::Producer';

    has '+type' => ( default => 'some_type' );

    sub transform {
        my ($self,$header,$arg) = @_;

        $header->{destination} = delete $arg->{destination};

        return ($header, {});
    }
};

my $tester = Test::NAP::Messaging->new({
    trace_basedir => 't/tmp/amq_dump_dir',
});

my $e = exception {
    $tester->transform_and_send('MyProducer',{})
};
cmp_deeply($e,
           all(
               isa('Net::Stomp::Producer::Exceptions::Invalid'),
               methods(
                   reason => re(qr{\bdestination\b}),
               ),
           ),
           'sending failed as expected');

$tester->clear_destination('/queue/foo');

$e = exception {
    $tester->transform_and_send('MyProducer',{destination=>'/queue/foo'})
};
cmp_deeply($e,undef,
           'sending worked as expected');

$tester->assert_messages({
    destination => '/queue/foo',
    assert_header => superhashof({
        type => 'some_type',
    }),
});

done_testing();
