#!perl
use NAP::policy 'test';
use Test::NAP::Messaging;

my ($tester,$app_entry_point) = Test::NAP::Messaging->new_with_app({
    app_class => 'MyApp',
    config_file => 't/lib/myapp.conf',
});

$tester->clear_destination;

MyApp->log->disable('error','warn')
    unless $ENV{TEST_VERBOSE};

subtest 'malformed message' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/the_actual_queue_name',
        { bad => 'input' },
        { type => 'my_message_type' },
    );
    is($response->code,400,'message was consumed, and status 400 returned');

    $tester->assert_messages({
        destination => 'queue/DLQ.failed-validation.queue/the_actual_queue_name',
        filter_header => superhashof({type => 'error-my_message_type'}),
        assert_count => 1,
        assert_body => {
            original_message => { bad => 'input' },
            original_headers => superhashof({ type => 'my_message_type' }),
            destination => '/queue/the_actual_queue_name',
            consumer => 'MyApp::Consumer::One',
            method => ignore(),
            errors => [re(qr{^Validation error\b.*?\bfound unexpected entries: bad\b})],
            status => 400,
        },
    },'error is in DLQ');
};

subtest 'exception in processing' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/stringy',
        { value => 'die' },
        { type => 'string_message' },
    );
    is($response->code,500,'message was consumed, and status 500 returned');

    $tester->assert_messages({
        destination => 'queue/DLQ.queue/stringy',
        filter_header => superhashof({type => 'error-string_message'}),
        assert_count => 1,
        assert_body => {
            original_message => { value => 'die' },
            original_headers => superhashof({ type => 'string_message' }),
            destination => '/queue/stringy',
            consumer => 'MyApp::Consumer::Two',
            method => ignore(),
            errors => [re(qr{^testing death at\b})],
            status => 500,
        },
    },'error is in DLQ');
};

subtest 'message for unhandled destination' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/unknown',
        { },
        { type => 'whatever' },
    );
    is($response->code,404,'message was consumed, and status 404 returned');

    $tester->assert_messages({
        destination => 'queue/DLQ.queue/unknown',
        filter_header => superhashof({type => 'error-whatever'}),
        assert_count => 1,
        assert_body => {
            original_message => { },
            original_headers => superhashof({ type => 'whatever' }),
            destination => '/queue/unknown',
            consumer => undef,
            method => ignore(),
            errors => [re(qr{^unknown destination\b})],
            status => 404,
        },
    },'error is in DLQ');
};

subtest 'message of unknown type' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/the_actual_queue_name',
        { },
        { type => 'whatever' },
    );
    is($response->code,404,'message was consumed, and status 404 returned');

    $tester->assert_messages({
        destination => 'queue/DLQ.queue/the_actual_queue_name',
        filter_header => superhashof({type => 'error-whatever'}),
        assert_count => 1,
        assert_body => {
            original_message => { },
            original_headers => superhashof({ type => 'whatever' }),
            destination => '/queue/the_actual_queue_name',
            consumer => undef,
            method => ignore(),
            errors => [re(qr{^unknown message type\b})],
            status => 404,
        },
    },'error is in DLQ');
};

done_testing();
