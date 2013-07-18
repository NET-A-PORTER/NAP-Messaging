package App;
use NAP::policy 'tt';
use Test::NAP::Messaging;

my ($tester,$app_entry_point) = Test::NAP::Messaging->new_with_app({
    app_class => 'MyApp',
    config_file => 't/lib/myapp.conf',
});

sub test_it {
    $tester->request(
        $app_entry_point,
        'queue/the_actual_queue_name',
        { count => 13 },
        { type => 'my_message_type' },
    );
    $tester->request(
        $app_entry_point,
        'queue/stringy',
        { value => "\x{1F662}" },
        { type => 'string_message' },
    );
    $tester->request_with_extra_fields(
        $app_entry_point,
        'queue/stringy',
        { value => "\x{1F662}" },
        { type => 'padded_message' },
    );
    $tester->request(
        $app_entry_point,
        'queue/deep',
        { count => 27 },
        { type => 'my_message_type' },
    );
}
