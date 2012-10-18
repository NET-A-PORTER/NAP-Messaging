#!perl
use NAP::policy 'test';
use Test::Fatal;
use Test::NAP::Messaging;

my $dest = '/queue/foo';

package MyProducer {
    use NAP::policy 'class';
    with 'NAP::Messaging::Role::Producer';

    has '+destination' => ( default => $dest );
    has '+type' => ( default => 'my_type' );

    sub transform {
        my ($self,$header,$arg) = @_;

        return ($header, $arg);
    }
};

my $tester = Test::NAP::Messaging->new({
    trace_basedir => 't/tmp/amq_dump_dir',
});

$tester->clear_destination($dest);

$tester->transform_and_send(
    MyProducer->new(),
    {foo=>1}
);

$tester->assert_messages({
    destination => $dest,
    assert_header => superhashof({
        type => 'my_type',
    }),
    assert_body => {
        foo => 1,
        '@type' => 'my_type',
    },
}, '@type is there');

$tester->clear_destination($dest);

$tester->transform_and_send(
    MyProducer->new({set_at_type=>0}),
    {foo=>1}
);

$tester->assert_messages({
    destination => $dest,
    assert_header => superhashof({
        type => 'my_type',
    }),
    assert_body => {
        foo => 1,
    },
}, '@type is no longer there');

done_testing();
