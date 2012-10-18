#!perl
use NAP::policy 'test';
use Test::Fatal;
use Test::NAP::Messaging;

package MyProducer {
    use NAP::policy 'class';
    with 'NAP::Messaging::Role::Producer';

    our $calls = 0;

    sub message_spec {++$calls; +{
        type => '//rec',
        required => { value => '//int'}
    } }

    has '+destination' => ( default => 'my_destination' );
    has '+type' => ( default => 'my_response' );

    sub transform {
        my ($self,$header,$arg) = @_;

        return ($header, $arg);
    }
};

my $tester = Test::NAP::Messaging->new({
    trace_basedir => 't/tmp/amq_dump_dir',
});

is($MyProducer::calls,0,'validator has not been precompiled');

my $e = exception {
    $tester->transform_and_send('MyProducer',
                                {value=>'barf'})
};
cmp_deeply($e,
           all(
               isa('Net::Stomp::Producer::Exceptions::Invalid'),
               methods(
                   reason => re(qr{\bvalidation\b}),
                   previous_exception => re(qr{\bvalue is not a number\b}),
               ),
           ),
           'validation failed as expected');

is($MyProducer::calls,1,'validator has been compiled');

$e = exception {
    $tester->transform_and_send('MyProducer',
                                {value=>1})
};
cmp_deeply($e,undef,
           'validation passed');

is($MyProducer::calls,1,'validator has not been re-compiled');

done_testing();
