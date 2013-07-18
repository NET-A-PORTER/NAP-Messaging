#!perl
use NAP::policy 'test','tt';
use Test::NAP::Messaging;

package MyProducer {
    use NAP::policy 'class';
    with 'NAP::Messaging::Role::Producer';

    has '+type' => ( default => 'some_type' );
    has '+destination' => ( default => '/queue/foo' );

    sub transform {
        my ($self,$header,$arg) = @_;

        $header = {%$header,%$arg};

        return ($header, {});
    }
};

my $tester = Test::NAP::Messaging->new({
    trace_basedir => 't/tmp/amq_dump_dir',
});

warning_like {
    $tester->transform_and_send('MyProducer',{
        JMSType => 'foo',
    })
} qr{^MyProducer\S* set "JMSType"},
    'warn when setting JMSType';

warning_like {
    $tester->transform_and_send('MyProducer',{
        JMSType => 'foo',
        type => 'foo',
    })
} qr{^MyProducer\S* set both "JMSType" and "type".+\bsame value\b},
    'warn when setting JMSType and type';

throws_ok {
    $tester->transform_and_send('MyProducer',{
        JMSType => 'foo',
        type => 'bar'
    })
} qr{^MyProducer\S* set both "JMSType" and "type".+\bdifferent values\b},
    'die when setting JMSType and type to different values';

done_testing();
