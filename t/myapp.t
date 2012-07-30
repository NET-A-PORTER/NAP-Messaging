#!perl
use NAP::policy 'test';
use Test::NAP::Messaging;

my ($tester,$app_entry_point) = Test::NAP::Messaging->new_with_app({
    app_class => 'MyApp',
    config_file => 't/lib/myapp.conf',
});

$tester->clear_destination;

subtest 'passing numbers' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/the_actual_queue_name',
        { count => 13 },
        { type => 'my_message_type' },
    );
    ok($response->is_success,'message was consumed');

    $tester->assert_messages({
        destination => 'queue/the_actual_destination',
        filter_header => superhashof({type => 'my_response'}),
        assert_count => 1,
        assert_body => superhashof({ value => 14 }),
    },'reply was sent');
};

subtest 'passing strings' => sub {
    my $response = $tester->request(
        $app_entry_point,
        'queue/stringy',
        { value => "\x{1F662}" },
        { type => 'string_message' },
    );
    ok($response->is_success,'message was consumed');

    $tester->assert_messages({
        destination => 'queue/string-reply',
        filter_header => superhashof({type => 'string_response'}),
        assert_count => 1,
        assert_body => superhashof({ response => "\x{1F662}\x{1F603}" }),
    },'reply was sent');
};

done_testing();
